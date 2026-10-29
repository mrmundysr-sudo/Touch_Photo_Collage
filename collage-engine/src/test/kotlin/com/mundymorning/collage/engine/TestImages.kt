package com.mundymorning.collage.engine

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import androidx.exifinterface.media.ExifInterface
import java.io.File

object TestImages {
    /** Left half red, right half blue, saved as JPEG with the given EXIF orientation. */
    fun redBlueJpeg(file: File, w: Int = 40, h: Int = 20, exif: Int = 1) {
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        val p = Paint()
        p.color = Color.rgb(255, 0, 0); c.drawRect(0f, 0f, w / 2f, h.toFloat(), p)
        p.color = Color.rgb(0, 0, 255); c.drawRect(w / 2f, 0f, w.toFloat(), h.toFloat(), p)
        file.outputStream().use { bmp.compress(Bitmap.CompressFormat.JPEG, 100, it) }
        if (exif != 1) ExifInterface(file.path).apply {
            setAttribute(ExifInterface.TAG_ORIENTATION, exif.toString()); saveAttributes()
        }
    }

    fun solidJpeg(file: File, w: Int, h: Int, color: Int) {
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        bmp.eraseColor(color)
        file.outputStream().use { bmp.compress(Bitmap.CompressFormat.JPEG, 95, it) }
    }

    fun sha(f: File): String = java.security.MessageDigest.getInstance("SHA-256").digest(f.readBytes()).joinToString("") { "%02x".format(it) }
}
