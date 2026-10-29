package com.mundymorning.collage.engine

import com.mundymorning.collage.engine.color.ColorMath
import com.mundymorning.collage.engine.color.Sharpen
import com.mundymorning.collage.engine.project.Adjustments
import com.mundymorning.collage.engine.project.FilterType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ColorTest {
    private fun apply(m: FloatArray, r: Float, g: Float, b: Float): Triple<Float, Float, Float> = Triple(
        m[0] * r + m[1] * g + m[2] * b + m[4], m[5] * r + m[6] * g + m[7] * b + m[9], m[10] * r + m[11] * g + m[12] * b + m[14],
    )

    @Test fun neutralSettingsAreIdentity() {
        assertTrue(ColorMath.isIdentity(ColorMath.forCell(Adjustments(), FilterType.NONE)))
    }

    @Test fun blackAndWhiteRemovesColour() {
        val (r, g, b) = apply(ColorMath.forCell(Adjustments(), FilterType.BLACK_WHITE), 200f, 40f, 90f)
        assertEquals(r, g, 1f); assertEquals(g, b, 1f)
    }

    @Test fun brightnessAndContrastMoveValuesInTheRightDirection() {
        assertTrue(apply(ColorMath.brightness(0.5f), 100f, 100f, 100f).first > 100f)
        assertTrue(apply(ColorMath.brightness(-0.5f), 100f, 100f, 100f).first < 100f)
        assertTrue(apply(ColorMath.contrast(0.5f), 200f, 200f, 200f).first > 200f)
        assertTrue(apply(ColorMath.contrast(0.5f), 50f, 50f, 50f).first < 50f)
        assertEquals(127.5f, apply(ColorMath.contrast(0.7f), 127.5f, 127.5f, 127.5f).first, 0.5f)
    }

    @Test fun saturationZeroIsGreyAndWarmthShiftsRedBlue() {
        val (r, g, b) = apply(ColorMath.saturation(0f), 255f, 0f, 0f)
        assertEquals(r, g, 0.5f); assertEquals(g, b, 0.5f)
        val warm = apply(ColorMath.warmth(1f), 100f, 100f, 100f)
        assertTrue(warm.first > 100f && warm.third < 100f)
    }

    @Test fun vintageIsNotIdentityAndKeepsAlpha() {
        val m = ColorMath.filter(FilterType.VINTAGE)
        assertTrue(!ColorMath.isIdentity(m)); assertEquals(1f, m[18], 1e-4f)
    }

    @Test fun sharpenLeavesFlatAreasAndBoostsEdges() {
        val w = 8; val h = 8
        val flat = IntArray(w * h) { 0xFF808080.toInt() }
        assertTrue(Sharpen.apply(flat, w, h, 1f).contentEquals(flat))
        val edge = IntArray(w * h) { if (it % w < 4) 0xFF707070.toInt() else 0xFF909090.toInt() }
        val out = Sharpen.apply(edge, w, h, 1f)
        val row = 3 * w
        assertTrue((out[row + 3] and 0xFF) < 0x70); assertTrue((out[row + 4] and 0xFF) > 0x90)
        assertEquals(0xFF, out[row + 3] ushr 24)
    }
}
