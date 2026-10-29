package com.mundymorning.collage.engine.color

import com.mundymorning.collage.engine.project.Adjustments
import com.mundymorning.collage.engine.project.FilterType

/**
 * 4x5 colour matrices in android.graphics.ColorMatrix layout (row-major, offsets in 0..255), kept as plain float
 * arrays so they can be unit-tested without Android.
 */
object ColorMath {
    private val IDENTITY = floatArrayOf(
        1f, 0f, 0f, 0f, 0f,
        0f, 1f, 0f, 0f, 0f,
        0f, 0f, 1f, 0f, 0f,
        0f, 0f, 0f, 1f, 0f,
    )

    fun identity(): FloatArray = IDENTITY.copyOf()

    fun isIdentity(m: FloatArray): Boolean = m.indices.all { kotlin.math.abs(m[it] - IDENTITY[it]) < 1e-4f }

    /** Result of applying [a] first and then [b]. */
    fun concat(a: FloatArray, b: FloatArray): FloatArray {
        val out = FloatArray(20)
        for (row in 0 until 4) {
            for (col in 0 until 5) {
                var v = 0f
                for (k in 0 until 4) v += b[row * 5 + k] * a[k * 5 + col]
                if (col == 4) v += b[row * 5 + 4]
                out[row * 5 + col] = v
            }
        }
        return out
    }

    fun brightness(b: Float): FloatArray = identity().also {
        val o = b * 0.4f * 255f
        it[4] = o; it[9] = o; it[14] = o
    }

    fun contrast(c: Float): FloatArray {
        val s = if (c >= 0f) 1f + c * 0.8f else 1f + c * 0.6f
        val o = 127.5f * (1f - s)
        return floatArrayOf(
            s, 0f, 0f, 0f, o,
            0f, s, 0f, 0f, o,
            0f, 0f, s, 0f, o,
            0f, 0f, 0f, 1f, 0f,
        )
    }

    /** [s] = 1 is neutral, 0 is greyscale, 2 is double saturation. */
    fun saturation(s: Float): FloatArray {
        val lr = 0.2126f; val lg = 0.7152f; val lb = 0.0722f
        val inv = 1f - s
        return floatArrayOf(
            lr * inv + s, lg * inv, lb * inv, 0f, 0f,
            lr * inv, lg * inv + s, lb * inv, 0f, 0f,
            lr * inv, lg * inv, lb * inv + s, 0f, 0f,
            0f, 0f, 0f, 1f, 0f,
        )
    }

    fun warmth(w: Float): FloatArray = floatArrayOf(
        1f + 0.22f * w, 0f, 0f, 0f, 0f,
        0f, 1f + 0.04f * w, 0f, 0f, 0f,
        0f, 0f, 1f - 0.22f * w, 0f, 0f,
        0f, 0f, 0f, 1f, 0f,
    )

    private val SEPIA = floatArrayOf(
        0.393f, 0.769f, 0.189f, 0f, 0f,
        0.349f, 0.686f, 0.168f, 0f, 0f,
        0.272f, 0.534f, 0.131f, 0f, 0f,
        0f, 0f, 0f, 1f, 0f,
    )

    fun filter(type: FilterType): FloatArray = when (type) {
        FilterType.NONE -> identity()
        FilterType.BLACK_WHITE -> concat(saturation(0f), contrast(0.12f))
        FilterType.SEPIA -> SEPIA.copyOf()
        FilterType.VINTAGE -> listOf(saturation(0.65f), warmth(0.5f), contrast(-0.18f), brightness(0.06f))
            .reduce { acc, m -> concat(acc, m) }
            .also { it[14] += 8f } // slightly lifted, cool shadows
        FilterType.FADE -> concat(contrast(-0.25f), concat(saturation(0.85f), brightness(0.08f)))
        FilterType.VIVID -> concat(saturation(1.45f), contrast(0.12f))
        FilterType.COOL -> warmth(-0.6f)
        FilterType.WARM -> warmth(0.6f)
    }

    /** Full matrix for a cell: filter first, then the user's adjustments. */
    fun forCell(adj: Adjustments, filter: FilterType): FloatArray {
        var m = filter(filter)
        if (adj.brightness != 0f) m = concat(m, brightness(adj.brightness))
        if (adj.contrast != 0f) m = concat(m, contrast(adj.contrast))
        if (adj.saturation != 0f) m = concat(m, saturation(1f + adj.saturation))
        if (adj.warmth != 0f) m = concat(m, warmth(adj.warmth))
        return m
    }
}

/** Simple unsharp-mask sharpening on ARGB pixel arrays. */
object Sharpen {
    /** @param amount 0 = unchanged, 1 = strong. Returns a new array; alpha is preserved. */
    fun apply(src: IntArray, w: Int, h: Int, amount: Float): IntArray {
        if (amount <= 0f || w < 3 || h < 3) return src.copyOf()
        val out = src.copyOf()
        val k = amount * 1.6f
        for (y in 1 until h - 1) {
            for (x in 1 until w - 1) {
                val i = y * w + x
                var r = 0; var g = 0; var b = 0
                for (dy in -1..1) for (dx in -1..1) {
                    val p = src[i + dy * w + dx]
                    r += (p shr 16) and 0xFF; g += (p shr 8) and 0xFF; b += p and 0xFF
                }
                val c = src[i]
                val cr = (c shr 16) and 0xFF; val cg = (c shr 8) and 0xFF; val cb = c and 0xFF
                val nr = (cr + k * (cr - r / 9f)).toInt().coerceIn(0, 255)
                val ng = (cg + k * (cg - g / 9f)).toInt().coerceIn(0, 255)
                val nb = (cb + k * (cb - b / 9f)).toInt().coerceIn(0, 255)
                out[i] = (c and 0xFF000000.toInt()) or (nr shl 16) or (ng shl 8) or nb
            }
        }
        return out
    }
}
