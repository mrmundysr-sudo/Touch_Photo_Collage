package com.mundymorning.collage.engine.io

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.util.LruCache
import com.mundymorning.collage.engine.project.PhotoRef
import com.mundymorning.collage.engine.transform.Orientation
import java.io.File

/** Source of decoded (not yet oriented) bitmaps for the renderer. */
interface BitmapProvider {
    /** Decode [ref] with the given power-of-two [sample]; null if unreadable. */
    fun get(ref: PhotoRef, sample: Int): Bitmap?

    /** Called when the renderer is finished with a bitmap obtained from [get]. */
    fun release(bitmap: Bitmap)
}

object BitmapLoader {

    /** Decode with a sample size; on OutOfMemory retries with a coarser sample (memory-pressure recovery). */
    fun decode(file: File, sample: Int): Bitmap? {
        var s = sample.coerceAtLeast(1)
        repeat(4) {
            try {
                val o = BitmapFactory.Options().apply {
                    inSampleSize = s
                    inPreferredConfig = Bitmap.Config.ARGB_8888
                }
                return BitmapFactory.decodeFile(file.path, o)
            } catch (e: OutOfMemoryError) {
                s *= 2
            }
        }
        return null
    }

    /** Upright (EXIF-applied) bitmap whose longest side is at most [maxSide]. For thumbnails and face detection. */
    fun decodeUpright(file: File, ref: PhotoRef, maxSide: Int): Bitmap? {
        var sample = 1
        while (maxOf(ref.width, ref.height) / (sample * 2) >= maxSide) sample *= 2
        val raw = decode(file, sample) ?: return null
        if (ref.exif == 1) return raw
        val aff = Orientation.exifAffine(raw.width.toFloat(), raw.height.toFloat(), ref.exif)
        val m = Matrix().apply { setValues(aff.toMatrixValues()) }
        val swap = Orientation.exifSwapsAxes(ref.exif)
        val out = Bitmap.createBitmap(if (swap) raw.height else raw.width, if (swap) raw.width else raw.height, Bitmap.Config.ARGB_8888)
        Canvas(out).drawBitmap(raw, m, Paint(Paint.FILTER_BITMAP_FLAG))
        raw.recycle()
        return out
    }
}

/** Decodes from the project's media folder, optionally caching decoded bitmaps (live preview) or not (export). */
class FileBitmapProvider(private val mediaDir: File, cacheBytes: Int = 0) : BitmapProvider {
    private val cache: LruCache<String, Bitmap>? = if (cacheBytes > 0) {
        object : LruCache<String, Bitmap>(cacheBytes) {
            override fun sizeOf(key: String, value: Bitmap) = value.byteCount
        }
    } else null

    override fun get(ref: PhotoRef, sample: Int): Bitmap? {
        val c = cache
        // any cached bitmap that is at least as detailed as requested will do
        if (c != null) {
            var s = sample
            while (s >= 1) {
                c.get("${ref.id}@$s")?.takeIf { !it.isRecycled }?.let { return it }
                s /= 2
            }
        }
        val bmp = BitmapLoader.decode(File(mediaDir, ref.file), sample) ?: return null
        c?.put("${ref.id}@$sample", bmp)
        return bmp
    }

    override fun release(bitmap: Bitmap) {
        if (cache == null) bitmap.recycle()
    }

    fun clear() { cache?.evictAll() }
}
