package com.mundymorning.touchgesture

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class OneFingerMathTest {
    private val k = 400f

    @Test fun slidingUpZoomsInAndDownZoomsOut() {
        assertTrue(OneFingerMath.zoomFactor(-50f, k) > 1f)
        assertTrue(OneFingerMath.zoomFactor(50f, k) < 1f)
        assertEquals(1f, OneFingerMath.zoomFactor(0f, k), 0f)
    }

    @Test fun oneDoublingDistanceDoublesAndHalves() {
        assertEquals(2f, OneFingerMath.zoomFactor(-k, k), 1e-4f)
        assertEquals(0.5f, OneFingerMath.zoomFactor(k, k), 1e-4f)
    }

    @Test fun smallMovementsGiveSmallChanges() {
        val f = OneFingerMath.zoomFactor(-2f, k)
        assertTrue(f > 1f && f < 1.01f)
    }

    @Test fun isProportionalAndReversible() {
        var z = 1f
        repeat(100) { z *= OneFingerMath.zoomFactor(-3f, k) }
        assertEquals(OneFingerMath.zoomFactor(-300f, k), z, 1e-3f)
        assertEquals(1f, OneFingerMath.zoomFactor(-120f, k) * OneFingerMath.zoomFactor(120f, k), 1e-5f)
    }

    @Test fun travelIsTheInverseOfFactor() {
        for (d in listOf(-200f, -7f, 13f, 90f)) assertEquals(d, OneFingerMath.travelFor(OneFingerMath.zoomFactor(d, k), k), 1e-2f)
    }

    @Test fun zoomIsClampedToLimits() {
        assertEquals(8f, OneFingerMath.clampZoom(7f, 4f, 1f, 8f), 0f)
        assertEquals(1f, OneFingerMath.clampZoom(1.2f, 0.1f, 1f, 8f), 0f)
    }

    @Test fun instructionAlwaysNamesTheMode() {
        assertTrue(TouchMode.PAN.instruction().startsWith("PAN"))
        assertTrue(TouchMode.ZOOM.instruction().startsWith("ZOOM"))
        assertTrue(TouchMode.ZOOM.instruction(hasTarget = false).contains("Tap a photo"))
    }
}
