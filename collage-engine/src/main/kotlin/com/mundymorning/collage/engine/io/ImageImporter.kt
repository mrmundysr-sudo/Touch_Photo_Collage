package com.mundymorning.collage.engine.io

import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.exifinterface.media.ExifInterface
import com.mundymorning.collage.engine.project.PhotoRef
import java.io.File
import java.io.IOException
import java.util.UUID

class ImportException(message: String, cause: Throwable? = null) : IOException(message, cause)

/**
 * Copies a picked photo into private app storage (read-only use of the source URI; the original is never opened for
 * writing). Working from a private copy keeps projects re-openable after the picker's temporary URI grant expires.
 */
class ImageImporter(private val context: Context, private val mediaDir: File) {

    init { mediaDir.mkdirs() }

    fun import(uri: Uri): PhotoRef {
        val id = UUID.randomUUID().toString()
        val name = "$id.img"
        val tmp = File(mediaDir, "$name.tmp")
        val dest = File(mediaDir, name)
        try {
            val input = context.contentResolver.openInputStream(uri) ?: throw ImportException("Cannot open photo")
            input.use { i -> tmp.outputStream().use { o -> i.copyTo(o, 64 * 1024) } }
            val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(tmp.path, opts)
            if (opts.outWidth <= 0 || opts.outHeight <= 0) throw ImportException("Not a readable image")
            val exif = readExifOrientation(tmp)
            if (!tmp.renameTo(dest)) throw ImportException("Cannot store photo")
            return PhotoRef(id, name, opts.outWidth, opts.outHeight, exif)
        } catch (e: ImportException) {
            tmp.delete(); throw e
        } catch (e: Exception) {
            tmp.delete(); throw ImportException("Could not import photo: ${e.message}", e)
        }
    }

    companion object {
        fun readExifOrientation(f: File): Int = try {
            f.inputStream().use {
                ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
            }.let { if (it in 1..8) it else 1 }
        } catch (e: Exception) {
            1
        }
    }
}
