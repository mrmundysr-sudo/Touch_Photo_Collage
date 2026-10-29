package com.mundymorning.collage.engine

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.net.Uri
import androidx.test.core.app.ApplicationProvider
import com.mundymorning.collage.engine.io.FileBitmapProvider
import com.mundymorning.collage.engine.io.ImageImporter
import com.mundymorning.collage.engine.project.*
import com.mundymorning.collage.engine.render.CollageRenderer
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File
import kotlin.math.abs

/** The live (per-frame) cell painter must produce exactly what the full renderer produces. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34])
class LiveDrawTest {
    private fun setup(): Triple<CollageProject, CollageRenderer, FileBitmapProvider> {
        val ctx = ApplicationProvider.getApplicationContext<Context>()
        val root = File(ctx.cacheDir, "live-${System.nanoTime()}").apply { mkdirs() }
        val store = ProjectStore(root)
        val imp = ImageImporter(ctx, store.mediaDir)
        val refs = List(3) { i ->
            val f = File(root, "s$i.jpg")
            TestImages.redBlueJpeg(f, 300, 200, if (i == 1) 6 else 1)
            imp.import(Uri.fromFile(f))
        }
        val p = ProjectOps.create(refs, ProjectMode.COLLAGE, 0L).let {
            it.copy(style = CollageStyle(0.02f, 0.02f, 0.05f), background = Background(color1 = Color.WHITE),
                cells = it.cells.mapIndexed { i, c -> if (i == 0) c.copy(caption = CellCaption("Mum", "", "")) else c })
        }
        val provider = FileBitmapProvider(store.mediaDir, 32 * 1024 * 1024)
        return Triple(p, CollageRenderer(provider), provider)
    }

    private fun regionDiff(a: Bitmap, b: Bitmap, r: com.mundymorning.collage.engine.model.FRect): Int {
        var worst = 0
        for (y in r.t.toInt() + 3 until r.b.toInt() - 3 step 2) for (x in r.l.toInt() + 3 until r.r.toInt() - 3 step 2) {
            val p = a.getPixel(x, y); val q = b.getPixel(x, y)
            worst = maxOf(worst, abs(Color.red(p) - Color.red(q)), abs(Color.green(p) - Color.green(q)), abs(Color.blue(p) - Color.blue(q)))
        }
        return worst
    }

    @Test fun liveDrawMatchesFullRenderForTheSameCropAndChangesWithTheCrop() {
        val (p, renderer, provider) = setup()
        val w = 600; val h = 600
        val full = renderer.render(p, w, h)
        val rect = CollageRenderer.cellRects(p, w, h)[0]
        val ref = p.cells[0].photo!!
        val bmp = provider.get(ref, 1)!!

        val same = full.copy(Bitmap.Config.ARGB_8888, true)
        renderer.drawCellLive(Canvas(same), p, 0, p.cells[0], bmp, w, h)
        assertTrue("same crop -> identical pixels (diff ${regionDiff(full, same, rect)})", regionDiff(full, same, rect) <= 3)

        val zoomed = full.copy(Bitmap.Config.ARGB_8888, true)
        renderer.drawCellLive(Canvas(zoomed), p, 0, p.cells[0].copy(zoom = 3.3f, cx = 0.7f, cy = 0.4f), bmp, w, h)
        assertTrue("different crop -> different pixels", regionDiff(full, zoomed, rect) > 40)

        // and it matches a full render at that crop, so live == final
        val proj2 = p.copy(cells = p.cells.mapIndexed { i, c -> if (i == 0) c.copy(zoom = 3.3f, cx = 0.7f, cy = 0.4f) else c })
        val full2 = renderer.render(proj2, w, h)
        assertTrue("live matches final render (diff ${regionDiff(full2, zoomed, rect)})", regionDiff(full2, zoomed, rect) <= 3)
    }

    @Test fun liveDrawLeavesOtherCellsUntouched() {
        val (p, renderer, provider) = setup()
        val w = 600; val h = 600
        val full = renderer.render(p, w, h)
        val rects = CollageRenderer.cellRects(p, w, h)
        val bmp = provider.get(p.cells[0].photo!!, 1)!!
        val live = full.copy(Bitmap.Config.ARGB_8888, true)
        renderer.drawCellLive(Canvas(live), p, 0, p.cells[0].copy(zoom = 5f), bmp, w, h)
        assertTrue(regionDiff(full, live, rects[1]) == 0)
        assertTrue(regionDiff(full, live, rects[2]) == 0)
    }
}
