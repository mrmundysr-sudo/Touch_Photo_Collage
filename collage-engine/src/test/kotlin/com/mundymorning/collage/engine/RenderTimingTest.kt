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
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

/**
 * CPU timing of the preview render on the JVM's software canvas. This is NOT a phone measurement (phones differ and
 * draw live gestures on the GPU); it exists to show relative cost: full composite vs. one cell.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34])
class RenderTimingTest {
    @Test fun report() {
        val ctx = ApplicationProvider.getApplicationContext<Context>()
        val root = File(ctx.cacheDir, "timing-${System.nanoTime()}").apply { mkdirs() }
        val store = ProjectStore(root)
        val imp = ImageImporter(ctx, store.mediaDir)
        val refs = List(4) { i ->
            val f = File(root, "s$i.jpg")
            val b = Bitmap.createBitmap(3000, 2000, Bitmap.Config.ARGB_8888)
            Canvas(b).drawColor(Color.rgb(40 * i + 20, 120, 200 - 30 * i))
            f.outputStream().use { b.compress(Bitmap.CompressFormat.JPEG, 85, it) }
            imp.import(Uri.fromFile(f))
        }
        val p = ProjectOps.create(refs, ProjectMode.COLLAGE, 0L)
        val renderer = CollageRenderer(FileBitmapProvider(store.mediaDir, 64 * 1024 * 1024))
        repeat(3) { renderer.render(p, 1000, 1000) }
        val n = 20
        val t0 = System.nanoTime()
        repeat(n) { renderer.render(p, 1000, 1000) }
        val full = (System.nanoTime() - t0) / n / 1e6
        val provider2 = FileBitmapProvider(store.mediaDir, 64 * 1024 * 1024)
        val r2 = CollageRenderer(provider2)
        val bmp = provider2.get(p.cells[0].photo!!, 2)!!
        val target = Bitmap.createBitmap(1000, 1000, Bitmap.Config.ARGB_8888)
        val cv = Canvas(target)
        repeat(20) { r2.drawCellLive(cv, p, 0, p.cells[0], bmp, 1000, 1000) }
        val t1 = System.nanoTime()
        repeat(n) { i -> r2.drawCellLive(cv, p, 0, p.cells[0].copy(zoom = 1f + i * 0.05f), bmp, 1000, 1000) }
        val live = (System.nanoTime() - t1) / n / 1e6
        println("TIMING live single-cell repaint (software canvas proxy for the GPU path): %.1f ms/frame".format(live))
        println("TIMING full-composite 1000px x4 photos: %.1f ms/frame (software, warm cache)".format(full))
    }
}
