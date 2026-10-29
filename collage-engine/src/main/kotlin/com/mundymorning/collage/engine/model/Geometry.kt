package com.mundymorning.collage.engine.model

import kotlin.math.max
import kotlin.math.min

/**
 * Axis-aligned rectangle with float edges. Used both for normalised (0..1) coordinates and for pixels;
 * the surrounding API says which. Pure Kotlin so it can be unit-tested on the JVM.
 */
data class FRect(val l: Float, val t: Float, val r: Float, val b: Float) {
    val w: Float get() = r - l
    val h: Float get() = b - t
    val cx: Float get() = (l + r) / 2f
    val cy: Float get() = (t + b) / 2f
    val area: Float get() = w * h

    /** Rotate 90 degrees clockwise inside the unit square. */
    fun rotatedCw(): FRect = FRect(1f - b, l, 1f - t, r)

    /** Mirror left-right inside the unit square. */
    fun mirroredH(): FRect = FRect(1f - r, t, 1f - l, b)

    fun union(o: FRect): FRect = FRect(min(l, o.l), min(t, o.t), max(r, o.r), max(b, o.b))

    fun intersect(o: FRect): FRect? {
        val nl = max(l, o.l); val nt = max(t, o.t); val nr = min(r, o.r); val nb = min(b, o.b)
        return if (nr > nl && nb > nt) FRect(nl, nt, nr, nb) else null
    }

    /** True when the two rectangles share more than [eps] of area on both axes. */
    fun overlaps(o: FRect, eps: Float = 1e-4f): Boolean =
        min(r, o.r) - max(l, o.l) > eps && min(b, o.b) - max(t, o.t) > eps

    fun contains(x: Float, y: Float): Boolean = x >= l && x <= r && y >= t && y <= b

    companion object {
        val UNIT = FRect(0f, 0f, 1f, 1f)
    }
}
