package com.mundymorning.collage.engine

import com.mundymorning.collage.engine.model.FRect
import com.mundymorning.collage.engine.transform.CropMath
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CropMathTest {
    private val eps = 1e-3f

    private fun pixelAspect(r: CropMath.Region, imgAspect: Float) = r.visW / r.visH * imgAspect

    @Test fun fillRegionHasCellAspectAndStaysInsidePhoto() {
        for (img in listOf(0.5f, 0.75f, 1f, 1.5f, 3f)) for (cell in listOf(0.5f, 1f, 1.7f)) for (z in listOf(1f, 2f, 5f)) {
            val r = CropMath.region(img, cell, z, 0.1f, 0.9f, fit = false)
            assertEquals("never distorts (img=$img cell=$cell z=$z)", cell, pixelAspect(r, img), 1e-3f)
            assertTrue(r.rect.l >= -eps && r.rect.t >= -eps && r.rect.r <= 1 + eps && r.rect.b <= 1 + eps)
        }
    }

    @Test fun fitShowsWholePhotoWithoutDistortion() {
        for (img in listOf(0.5f, 1f, 2f)) for (cell in listOf(0.6f, 1f, 1.8f)) {
            val r = CropMath.region(img, cell, 1f, 0.2f, 0.2f, fit = true)
            assertEquals(cell, pixelAspect(r, img), 1e-3f)
            assertTrue("whole photo inside region", r.rect.l <= eps && r.rect.t <= eps && r.rect.r >= 1 - eps && r.rect.b >= 1 - eps)
            // photo is drawn uncropped: its destination keeps the photo's own aspect ratio
            val cellPx = FRect(0f, 0f, 1000f * cell, 1000f)
            val d = CropMath.destRect(r, cellPx)
            assertEquals(img, d.w / d.h, 1e-2f)
        }
    }

    @Test fun fillDestinationIsTheWholeCell() {
        val r = CropMath.region(1.5f, 1f, 1.7f, 0.4f, 0.6f, false)
        val d = CropMath.destRect(r, FRect(10f, 20f, 210f, 220f))
        assertEquals(10f, d.l, 1e-2f); assertEquals(210f, d.r, 1e-2f); assertEquals(20f, d.t, 1e-2f); assertEquals(220f, d.b, 1e-2f)
    }

    @Test fun panIsClampedToPhotoEdges() {
        val (cx, cy) = CropMath.pan(1.5f, 100f, 100f, 2f, 0.5f, 0.5f, false, dxPx = 100000f, dyPx = -100000f)
        val r = CropMath.region(1.5f, 1f, 2f, cx, cy, false)
        assertEquals(0f, r.rect.l, eps); assertEquals(1f, r.rect.b, eps)
    }

    @Test fun panMovesContentWithTheFinger() {
        // dragging the photo right by half the cell should move the visible window left by half its width
        val r0 = CropMath.region(1f, 1f, 2f, 0.5f, 0.5f, false)
        val (cx, _) = CropMath.pan(1f, 200f, 200f, 2f, 0.5f, 0.5f, false, dxPx = 100f, dyPx = 0f)
        assertEquals(r0.rect.cx - 0.5f * r0.visW, cx, eps)
    }

    @Test fun zoomAboutKeepsFocalContentStill() {
        val img = 1.3f; val cell = 1f
        val r0 = CropMath.region(img, cell, 1.5f, 0.5f, 0.5f, false)
        val (z, cx, cy) = CropMath.zoomAbout(img, cell, 1.5f, 0.5f, 0.5f, false, 3f, fx = 0.25f, fy = 0.75f)
        val r1 = CropMath.region(img, cell, z, cx, cy, false)
        val before = r0.rect.l + 0.25f * r0.visW
        val after = r1.rect.l + 0.25f * r1.visW
        assertEquals(before, after, eps)
        assertEquals(r0.rect.t + 0.75f * r0.visH, r1.rect.t + 0.75f * r1.visH, eps)
    }

    @Test fun zoomIsClamped() {
        assertEquals(1f, CropMath.clampZoom(0.2f), 0f)
        assertEquals(CropMath.MAX_ZOOM, CropMath.clampZoom(99f), 0f)
    }

    @Test fun sampleSizeNeverDropsBelowNeededResolution() {
        assertEquals(1, CropMath.sampleFor(1.5f))
        assertEquals(1, CropMath.sampleFor(0.9f))
        assertEquals(2, CropMath.sampleFor(0.5f))
        assertEquals(2, CropMath.sampleFor(0.4f))
        assertEquals(4, CropMath.sampleFor(0.25f))
        for (r in listOf(0.7f, 0.3f, 0.11f, 0.03f)) assertTrue(r * CropMath.sampleFor(r) <= 1f + 1e-6f) // decoded >= needed
    }
}
