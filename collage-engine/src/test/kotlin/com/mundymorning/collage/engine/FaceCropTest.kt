package com.mundymorning.collage.engine

import com.mundymorning.collage.engine.face.CropState
import com.mundymorning.collage.engine.face.FaceCrop
import com.mundymorning.collage.engine.face.FaceInput
import com.mundymorning.collage.engine.model.FRect
import com.mundymorning.collage.engine.transform.CropMath
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FaceCropTest {
    private fun faceAt(cx: Float, cy: Float, h: Float, aspect: Float): FRect {
        val w = h / aspect * 0.8f
        return FRect(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2)
    }

    private fun faceHeightInCell(input: FaceInput, s: CropState): Float {
        val r = CropMath.region(input.imgAspect, input.cellAspect, s.zoom, s.cx, s.cy, false)
        return FaceCrop.primary(input.faces)!!.h / r.visH
    }

    private fun faceCentreY(input: FaceInput, s: CropState): Float {
        val r = CropMath.region(input.imgAspect, input.cellAspect, s.zoom, s.cx, s.cy, false)
        return (FaceCrop.primary(input.faces)!!.cy - r.rect.t) / r.visH
    }

    @Test fun noFaceFallsBackToCentreCrop() {
        val s = FaceCrop.smart(FaceInput(1.5f, emptyList(), 1f))
        assertEquals(CropState(1f, 0.5f, 0.5f), s)
        assertEquals(listOf(CropState(1f, 0.5f, 0.5f)), FaceCrop.align(listOf(FaceInput(1.5f, emptyList(), 1f))))
    }

    @Test fun smartCropKeepsFacesVisibleEvenWhenOffCentre() {
        val input = FaceInput(0.6f, listOf(faceAt(0.5f, 0.1f, 0.12f, 0.6f)), cellAspect = 1.5f)
        val s = FaceCrop.smart(input)
        assertTrue(FaceCrop.facesVisible(input, s))
    }

    @Test fun alignMatchesFaceSizeAndHeightAcrossGenerations() {
        // a close-up portrait, a small face in a full-body shot and a landscape group photo
        val inputs = listOf(
            FaceInput(0.75f, listOf(faceAt(0.5f, 0.35f, 0.35f, 0.75f)), cellAspect = 0.9f),
            FaceInput(0.67f, listOf(faceAt(0.4f, 0.2f, 0.10f, 0.67f)), cellAspect = 0.9f),
            FaceInput(1.5f, listOf(faceAt(0.7f, 0.45f, 0.18f, 1.5f)), cellAspect = 0.9f),
        )
        val states = FaceCrop.align(inputs)
        val heights = inputs.indices.map { faceHeightInCell(inputs[it], states[it]) }
        for (h in heights) assertEquals("same face height", heights[0], h, 0.02f)
        inputs.indices.forEach { assertTrue("face visible $it", FaceCrop.facesVisible(inputs[it], states[it])) }
        // faces sit at the same height where the photo has room to move
        assertEquals(FaceCrop.TARGET_Y, faceCentreY(inputs[2], states[2]), 0.03f)
    }

    @Test fun alignNeverDistortsOnlyUniformZoom() {
        val inputs = listOf(
            FaceInput(0.75f, listOf(faceAt(0.5f, 0.4f, 0.2f, 0.75f)), 1f),
            FaceInput(1.33f, listOf(faceAt(0.5f, 0.4f, 0.1f, 1.33f)), 1f),
        )
        FaceCrop.align(inputs).forEachIndexed { i, s ->
            val r = CropMath.region(inputs[i].imgAspect, 1f, s.zoom, s.cx, s.cy, false)
            assertEquals(1f, r.visW / r.visH * inputs[i].imgAspect, 1e-3f)
        }
    }

    @Test fun photosWithoutFacesStayCentredWhileOthersAlign() {
        val inputs = listOf(FaceInput(1f, emptyList(), 1f), FaceInput(1f, listOf(faceAt(0.5f, 0.4f, 0.1f, 1f)), 1f))
        val s = FaceCrop.align(inputs)
        assertEquals(CropState(1f, 0.5f, 0.5f), s[0])
        assertTrue(s[1].zoom > 1f)
    }
}
