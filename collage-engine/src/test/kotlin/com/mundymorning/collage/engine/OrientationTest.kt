package com.mundymorning.collage.engine

import com.mundymorning.collage.engine.model.FRect
import com.mundymorning.collage.engine.transform.Orientation
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class OrientationTest {
    private val eps = 1e-3f

    @Test fun exifSixPutsRawTopLeftAtDisplayTopRight() {
        // 4x2 raw, rotated 90 CW -> 2x4 display; raw (0,0) lands at (2,0)
        val a = Orientation.totalAffine(4, 2, 6, 0, false)
        assertEquals(2f, a.mapX(0f, 0f), eps); assertEquals(0f, a.mapY(0f, 0f), eps)
        // raw bottom-left (0,2) -> bottom-right (0,0)? 90CW: bottom-left goes to top-left
        assertEquals(0f, a.mapX(0f, 2f), eps); assertEquals(0f, a.mapY(0f, 2f), eps)
    }

    @Test fun exifThreeIsHalfTurn() {
        val a = Orientation.totalAffine(4, 2, 3, 0, false)
        assertEquals(4f, a.mapX(0f, 0f), eps); assertEquals(2f, a.mapY(0f, 0f), eps)
    }

    @Test fun exifTwoMirrorsHorizontally() {
        val a = Orientation.totalAffine(4, 2, 2, 0, false)
        assertEquals(4f, a.mapX(0f, 0f), eps); assertEquals(0f, a.mapY(0f, 0f), eps)
    }

    @Test fun everyCombinationStaysInsideDisplayBounds() {
        for (exif in 1..8) for (rot in 0..3) for (mirror in listOf(false, true)) {
            val raw = 40 to 20
            val d = Orientation.displaySize(raw.first, raw.second, exif, rot)
            val a = Orientation.totalAffine(raw.first, raw.second, exif, rot, mirror)
            for ((x, y) in listOf(0f to 0f, 40f to 0f, 0f to 20f, 40f to 20f)) {
                val mx = a.mapX(x, y); val my = a.mapY(x, y)
                assertTrue("exif=$exif rot=$rot m=$mirror x=$mx", mx > -eps && mx < d.w + eps)
                assertTrue("exif=$exif rot=$rot m=$mirror y=$my", my > -eps && my < d.h + eps)
            }
            // area scale must be exactly 1 (no distortion): |det| == 1
            assertEquals(1f, Math.abs(a.a * a.d - a.b * a.c), eps)
        }
    }

    @Test fun faceRectsFollowRotationAndMirrorLikePixels() {
        // upright 100x50 image, a face near the left; user rotates 90 CW and mirrors.
        val face = FRect(0.1f, 0.2f, 0.3f, 0.6f)
        for (rot in 0..3) for (mirror in listOf(false, true)) {
            val disp = Orientation.toDisplay(face, rot, mirror)
            val d = Orientation.displaySize(100, 50, 1, rot)
            val a = Orientation.totalAffine(100, 50, 1, rot, mirror)
            val cx = a.mapX(face.cx * 100f, face.cy * 50f) / d.w
            val cy = a.mapY(face.cx * 100f, face.cy * 50f) / d.h
            assertEquals("rot=$rot m=$mirror cx", cx, disp.cx, eps)
            assertEquals("rot=$rot m=$mirror cy", cy, disp.cy, eps)
        }
    }

    @Test fun displaySizeSwapsForSideways() {
        assertEquals(20, Orientation.displaySize(40, 20, 6, 0).w)
        assertEquals(40, Orientation.displaySize(40, 20, 6, 1).w) // 6 + one more quarter = upright landscape
        assertEquals(20, Orientation.displaySize(40, 20, 1, 1).w)
    }
}
