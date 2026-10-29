package com.mundymorning.collage.engine.transform

import com.mundymorning.collage.engine.model.FRect

/** Size of an image after orientation has been applied. */
data class DisplaySize(val w: Int, val h: Int) {
    val aspect: Float get() = w.toFloat() / h.toFloat()
}

/**
 * Orientation maths shared by renderer, face logic and tests.
 *
 * Three stages turn raw decoded pixels into the "display space" in which every crop, face and gesture lives:
 *  1. EXIF orientation (values 1..8) so the photo is upright as the camera intended,
 *  2. user rotation in clockwise quarter turns,
 *  3. optional left/right mirroring.
 */
object Orientation {

    fun exifSwapsAxes(exif: Int): Boolean = exif in 5..8

    /** Display size for an image of raw size [w] x [h]. */
    fun displaySize(w: Int, h: Int, exif: Int, quarterTurns: Int): DisplaySize {
        val swap = exifSwapsAxes(exif) xor (Math.floorMod(quarterTurns, 4) % 2 == 1)
        return if (swap) DisplaySize(h, w) else DisplaySize(w, h)
    }

    /** Raw pixel coordinates (0..w, 0..h) -> upright (EXIF-applied) coordinates. */
    fun exifAffine(w: Float, h: Float, exif: Int): Affine = when (exif) {
        2 -> Affine(a = -1f, tx = w)
        3 -> Affine(a = -1f, d = -1f, tx = w, ty = h)
        4 -> Affine(d = -1f, ty = h)
        5 -> Affine(a = 0f, b = 1f, c = 1f, d = 0f)
        6 -> Affine(a = 0f, b = 1f, c = -1f, d = 0f, tx = h)
        7 -> Affine(a = 0f, b = -1f, c = -1f, d = 0f, tx = h, ty = w)
        8 -> Affine(a = 0f, b = -1f, c = 1f, d = 0f, ty = w)
        else -> Affine.IDENTITY
    }

    /** Clockwise quarter turns for an image of size [w] x [h] (the size *before* the turn). */
    fun rotateAffine(w: Float, h: Float, quarterTurns: Int): Affine = when (Math.floorMod(quarterTurns, 4)) {
        1 -> Affine(a = 0f, b = 1f, c = -1f, d = 0f, tx = h)
        2 -> Affine(a = -1f, d = -1f, tx = w, ty = h)
        3 -> Affine(a = 0f, b = -1f, c = 1f, d = 0f, ty = w)
        else -> Affine.IDENTITY
    }

    /** Raw pixels -> display space (pixel units of the display image). */
    fun totalAffine(rawW: Int, rawH: Int, exif: Int, quarterTurns: Int, mirror: Boolean): Affine {
        val upright = exifAffine(rawW.toFloat(), rawH.toFloat(), exif)
        val s1 = if (exifSwapsAxes(exif)) DisplaySize(rawH, rawW) else DisplaySize(rawW, rawH)
        val rot = rotateAffine(s1.w.toFloat(), s1.h.toFloat(), quarterTurns)
        val disp = displaySize(rawW, rawH, exif, quarterTurns)
        var m = upright.then(rot)
        if (mirror) m = m.then(Affine(a = -1f, tx = disp.w.toFloat()))
        return m
    }

    /** Move a rectangle given in upright (EXIF-applied) normalised coordinates into display space. */
    fun toDisplay(r: FRect, quarterTurns: Int, mirror: Boolean): FRect {
        var out = r
        repeat(Math.floorMod(quarterTurns, 4)) { out = out.rotatedCw() }
        if (mirror) out = out.mirroredH()
        return out
    }
}
