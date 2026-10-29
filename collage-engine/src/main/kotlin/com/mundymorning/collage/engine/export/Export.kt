package com.mundymorning.collage.engine.export

import android.content.ContentValues
import android.content.Context
import android.graphics.Bitmap
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import com.mundymorning.collage.engine.io.FileBitmapProvider
import com.mundymorning.collage.engine.layout.CanvasSpec
import com.mundymorning.collage.engine.layout.LayoutEngine
import com.mundymorning.collage.engine.project.BackgroundType
import com.mundymorning.collage.engine.project.CollageProject
import com.mundymorning.collage.engine.render.CollageRenderer
import java.io.File
import java.io.IOException
import java.io.OutputStream

enum class ExportFormat(val mime: String, val ext: String) { JPEG("image/jpeg", "jpg"), PNG("image/png", "png") }

enum class ExportQuality(val label: String, val longSide: Int, val jpegQuality: Int) {
    STANDARD("Standard", 2048, 90),
    MAXIMUM("Maximum", 4800, 100),
}

data class ExportRequest(
    val format: ExportFormat = ExportFormat.JPEG,
    val quality: ExportQuality = ExportQuality.STANDARD,
    /** Only honoured for PNG with a transparent background. */
    val transparent: Boolean = false,
)

data class ExportResult(val width: Int, val height: Int, val bytes: Long)

/** Chooses output pixel dimensions. Pure so it can be tested; memory budget keeps low-RAM devices alive. */
object ExportSizing {
    /** Bytes we allow the final bitmap to use (ARGB_8888 = 4 bytes/px). */
    fun budgetBytes(maxHeapBytes: Long): Long = (maxHeapBytes * 0.36).toLong().coerceAtLeast(24L * 1024 * 1024)

    fun size(spec: CanvasSpec, quality: ExportQuality, budgetBytes: Long): Pair<Int, Int> {
        var long = quality.longSide
        while (true) {
            val (w, h) = LayoutEngine.sizeForLongSide(spec, long)
            if (w.toLong() * h * 4L <= budgetBytes || long <= 1024) return w to h
            long = (long * 0.9f).toInt()
        }
    }
}

class Exporter(private val context: Context, private val mediaDir: File) {

    fun sizeFor(project: CollageProject, quality: ExportQuality): Pair<Int, Int> =
        ExportSizing.size(project.canvas, quality, ExportSizing.budgetBytes(Runtime.getRuntime().maxMemory()))

    /** Render and encode once; the pixels are encoded exactly one time so nothing is recompressed. */
    fun encode(project: CollageProject, req: ExportRequest, out: OutputStream): ExportResult {
        val (w, h) = sizeFor(project, req.quality)
        val keepAlpha = req.format == ExportFormat.PNG && req.transparent && project.background.type == BackgroundType.TRANSPARENT
        val renderer = CollageRenderer(FileBitmapProvider(mediaDir, 0))
        val bmp = try {
            renderer.render(project, w, h, CollageRenderer.Options(keepTransparent = keepAlpha))
        } catch (e: OutOfMemoryError) {
            throw IOException("Not enough memory for this size. Try Standard quality.", e)
        }
        try {
            val counting = CountingStream(out)
            val ok = when (req.format) {
                ExportFormat.JPEG -> bmp.compress(Bitmap.CompressFormat.JPEG, req.quality.jpegQuality, counting)
                ExportFormat.PNG -> bmp.compress(Bitmap.CompressFormat.PNG, 100, counting)
            }
            if (!ok) throw IOException("Encoding failed")
            counting.flush()
            return ExportResult(bmp.width, bmp.height, counting.count)
        } finally {
            bmp.recycle()
        }
    }

    fun exportToFile(project: CollageProject, req: ExportRequest, file: File): ExportResult {
        file.parentFile?.mkdirs()
        return try {
            file.outputStream().buffered().use { encode(project, req, it) }
        } catch (e: Exception) {
            file.delete(); throw e
        }
    }

    /** Saves into the system gallery (Pictures/Touch Photo Collage). Android 10+ needs no storage permission. */
    fun saveToGallery(project: CollageProject, req: ExportRequest): Uri {
        val name = fileName(project, req)
        val resolver = context.contentResolver
        if (Build.VERSION.SDK_INT >= 29) {
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, name)
                put(MediaStore.Images.Media.MIME_TYPE, req.format.mime)
                put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/$ALBUM")
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
            val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: throw IOException("Gallery unavailable")
            try {
                (resolver.openOutputStream(uri) ?: throw IOException("Gallery unavailable")).buffered().use { encode(project, req, it) }
                resolver.update(uri, ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) }, null, null)
            } catch (e: Exception) {
                resolver.delete(uri, null, null); throw e
            }
            return uri
        }
        @Suppress("DEPRECATION")
        val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), ALBUM)
        val file = File(dir, name)
        exportToFile(project, req, file)
        MediaScannerConnection.scanFile(context, arrayOf(file.path), arrayOf(req.format.mime), null)
        return Uri.fromFile(file)
    }

    /** Writes to the private cache and returns a content:// URI for the share sheet. */
    fun prepareShare(project: CollageProject, req: ExportRequest, authority: String): Uri {
        val dir = File(context.cacheDir, "shared").apply { mkdirs() }
        dir.listFiles()?.forEach { it.delete() }
        val f = File(dir, fileName(project, req))
        exportToFile(project, req, f)
        return FileProvider.getUriForFile(context, authority, f)
    }

    private fun fileName(p: CollageProject, req: ExportRequest): String {
        val base = p.name.replace(Regex("[^A-Za-z0-9._-]+"), "_").trim('_').ifEmpty { "collage" }.take(40)
        return "${base}_${System.currentTimeMillis()}.${req.format.ext}"
    }

    private class CountingStream(private val o: OutputStream) : OutputStream() {
        var count = 0L
        override fun write(b: Int) { o.write(b); count++ }
        override fun write(b: ByteArray, off: Int, len: Int) { o.write(b, off, len); count += len }
        override fun flush() = o.flush()
    }

    companion object { const val ALBUM = "Touch Photo Collage" }
}
