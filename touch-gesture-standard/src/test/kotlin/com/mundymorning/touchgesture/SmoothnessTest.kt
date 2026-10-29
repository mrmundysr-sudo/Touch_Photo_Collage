package com.mundymorning.touchgesture

import androidx.compose.ui.geometry.Offset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

class SmoothnessTest {
    private val dz = 12f
    private val k = 480f // px per doubling at 3x density, sensitivity 1

    @Test fun kneeIsContinuousAcrossTheThresholdAndIdentityBeyondIt() {
        assertEquals(Offset.Zero, GestureKnee.apply(Offset.Zero, dz))
        val just = GestureKnee.apply(Offset(dz - 0.001f, 0f), dz)
        val at = GestureKnee.apply(Offset(dz, 0f), dz)
        val past = GestureKnee.apply(Offset(dz + 0.001f, 0f), dz)
        assertEquals(dz, at.x, 1e-4f)
        assertTrue("no step at the threshold", abs(at.x - just.x) < 0.03f && abs(past.x - at.x) < 0.01f)
        assertEquals(50f, GestureKnee.apply(Offset(50f, 0f), dz).x, 0f)
        assertEquals(Offset(-30f, 40f), GestureKnee.apply(Offset(-30f, 40f), dz))
    }

    @Test fun kneeNeverLagsTheFingerByMoreThanAQuarterOfTheDeadzone() {
        var worst = 0f
        var v = 0f
        while (v < 3 * dz) { worst = maxOf(worst, v - GestureKnee.applyScalar(v, dz)); v += 0.01f }
        assertTrue("worst lag $worst", worst <= dz / 4f + 1e-3f)
    }

    @Test fun kneeIsMonotonicSoContentNeverMovesBackwardsWhileTheFingerMovesForward() {
        var prev = -1f
        var v = 0f
        while (v < 40f) { val e = GestureKnee.applyScalar(v, dz); assertTrue(e >= prev); prev = e; v += 0.05f }
    }

    @Test fun incrementalDeltasSumExactlyToTheTotalTravelSoNothingIsLostOrQuantised() {
        // per-event deltas (as the gesture loop computes them) must add up to the knee of the total
        var applied = 0f
        var sum = 0f
        val total = 137.3f
        var pos = 0f
        val rnd = java.util.Random(7)
        while (pos < total) {
            pos = minOf(total, pos + 0.2f + rnd.nextFloat() * 3f)
            val eff = GestureKnee.applyScalar(pos, dz)
            sum += eff - applied; applied = eff
        }
        assertEquals(total, sum, 1e-3f)
    }

    @Test fun everySingleSubPixelMovementChangesTheZoom() {
        var z = 1f
        val seen = HashSet<Float>()
        repeat(500) {
            val f = OneFingerMath.zoomFactor(-0.4f, k) // 0.4 px
            assertTrue(f > 1f)
            z *= f
            seen += z
        }
        assertEquals("no repeated (quantised) values", 500, seen.size)
        assertEquals(OneFingerMath.zoomFactor(-200f, k), z, 1e-3f)
    }

    @Test fun zoomFactorsMultiplyExactlyLikeOneBigMovementWithDoublePrecisionMath() {
        var z = 1.0
        repeat(2000) { z *= OneFingerMath.zoomFactor(-0.25f, k).toDouble() }
        assertEquals(Math.pow(2.0, 500.0 / k), z, 1e-3)
    }

    @Test fun sensitivityScalesTravelPerDoublingAndRoundTripsOnTheSlider() {
        val base = OneFingerMath.pxPerDoubling(3f, 1f)
        assertEquals(480f, base, 1e-3f)
        assertEquals(base / 2f, OneFingerMath.pxPerDoubling(3f, 2f), 1e-3f)
        assertEquals(base / 0.4f, OneFingerMath.pxPerDoubling(3f, OneFingerMath.SENSITIVITY_FINE), 1e-2f)
        for (s in listOf(0.25f, 0.4f, 1f, 2f, 3f)) assertEquals(s, OneFingerMath.sensitivityFromSlider(OneFingerMath.sliderFromSensitivity(s)), 1e-3f)
        assertEquals(OneFingerMath.SENSITIVITY_MAX, OneFingerMath.clampSensitivity(99f), 0f)
        assertEquals(OneFingerMath.SENSITIVITY_MIN, OneFingerMath.clampSensitivity(0f), 0f)
        // finer sensitivity = the same finger travel zooms less
        assertTrue(OneFingerMath.zoomFactor(-100f, OneFingerMath.pxPerDoubling(3f, 0.4f)) < OneFingerMath.zoomFactor(-100f, OneFingerMath.pxPerDoubling(3f, 1f)))
    }

    @Test fun frameStatsReportSteadySixtyFpsAndCountJank() {
        val s = FrameStats()
        var t = 1_000_000_000L
        repeat(61) { s.record(t); t += 16_666_667L }
        assertEquals(60f, s.fps, 1f); assertEquals(16.7f, s.avgMs, 0.1f); assertEquals(0, s.jankyFrames)
        s.record(t + 60_000_000L)
        assertEquals(1, s.jankyFrames); assertTrue(s.worstMs > 70f)
        assertTrue(s.summary().contains("fps"))
    }
}
