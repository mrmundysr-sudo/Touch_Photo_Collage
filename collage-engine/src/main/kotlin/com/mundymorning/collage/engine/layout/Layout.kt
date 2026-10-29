package com.mundymorning.collage.engine.layout

import com.mundymorning.collage.engine.model.FRect
import kotlin.math.abs
import kotlin.math.ln
import kotlin.math.min

/** A set of cells that exactly tiles the unit square. Photos are assigned to cells in list order. */
data class LayoutTemplate(
    val id: String,
    val name: String,
    val cells: List<FRect>,
) {
    val count: Int get() = cells.size
}

/** Aspect ratio of the output canvas, as an integer ratio so presets stay exact. */
data class CanvasSpec(val ratioW: Int, val ratioH: Int, val label: String = "$ratioW:$ratioH") {
    val aspect: Float get() = ratioW.toFloat() / ratioH.toFloat()

    companion object {
        val SQUARE = CanvasSpec(1, 1)
        val PORTRAIT_4_5 = CanvasSpec(4, 5)
        val PORTRAIT_3_4 = CanvasSpec(3, 4)
        val PORTRAIT_2_3 = CanvasSpec(2, 3)
        val STORY_9_16 = CanvasSpec(9, 16)
        val LANDSCAPE_4_3 = CanvasSpec(4, 3)
        val LANDSCAPE_3_2 = CanvasSpec(3, 2)
        val WIDE_16_9 = CanvasSpec(16, 9)

        val PRESETS = listOf(
            SQUARE, PORTRAIT_4_5, PORTRAIT_3_4, PORTRAIT_2_3, STORY_9_16, LANDSCAPE_4_3, LANDSCAPE_3_2, WIDE_16_9,
        )

        fun custom(w: Int, h: Int) = CanvasSpec(w.coerceIn(1, 99), h.coerceIn(1, 99))
    }
}

/** Resolves a normalised layout into pixel rectangles with margin and spacing. */
object LayoutEngine {
    private const val EDGE = 1e-4f

    /**
     * @param margin  outer margin in pixels
     * @param spacing gap between neighbouring cells in pixels
     */
    fun cellRects(layout: LayoutTemplate, canvasW: Float, canvasH: Float, margin: Float, spacing: Float): List<FRect> {
        val innerW = (canvasW - 2 * margin).coerceAtLeast(1f)
        val innerH = (canvasH - 2 * margin).coerceAtLeast(1f)
        val half = spacing / 2f
        return layout.cells.map { c ->
            var l = margin + c.l * innerW
            var t = margin + c.t * innerH
            var r = margin + c.r * innerW
            var b = margin + c.b * innerH
            if (c.l > EDGE) l += half
            if (c.t > EDGE) t += half
            if (c.r < 1f - EDGE) r -= half
            if (c.b < 1f - EDGE) b -= half
            // never collapse: keep at least 1px even for absurd spacing
            if (r - l < 1f) { val m = (l + r) / 2f; l = m - 0.5f; r = m + 0.5f }
            if (b - t < 1f) { val m = (t + b) / 2f; t = m - 0.5f; b = m + 0.5f }
            FRect(l, t, r, b)
        }
    }

    /** Pixel size (px) used for the spacing/margin/radius fractions: they are relative to the shorter canvas side. */
    fun unit(canvasW: Float, canvasH: Float): Float = min(canvasW, canvasH)

    /** Output size in pixels for a long side. */
    fun sizeForLongSide(spec: CanvasSpec, longSide: Int): Pair<Int, Int> {
        val a = spec.aspect
        return if (a >= 1f) longSide to Math.round(longSide / a).coerceAtLeast(1)
        else Math.round(longSide * a).coerceAtLeast(1) to longSide
    }
}

/** Generates tilings for any photo count. All results tile the unit square exactly (verified by tests). */
object LayoutGenerator {

    private fun distribute(n: Int, parts: Int): List<Int> {
        val base = n / parts
        val extra = n % parts
        return List(parts) { base + if (it < extra) 1 else 0 }
    }

    /** Horizontal rows; each row's cells share its width equally. */
    fun rows(n: Int, rowCount: Int, name: String? = null, id: String? = null): LayoutTemplate {
        val counts = distribute(n, rowCount)
        val cells = ArrayList<FRect>()
        var y = 0f
        counts.forEachIndexed { ri, k ->
            val y2 = if (ri == rowCount - 1) 1f else (ri + 1f) / rowCount
            for (i in 0 until k) cells += FRect(i.toFloat() / k, y, if (i == k - 1) 1f else (i + 1f) / k, y2)
            y = y2
        }
        return LayoutTemplate(id ?: "rows-$n-$rowCount", name ?: "$rowCount rows", cells)
    }

    /** Grid with [cols] columns; the last row is stretched so the whole canvas is filled. */
    fun gridWithColumns(n: Int, cols: Int): LayoutTemplate {
        val c = cols.coerceIn(1, n.coerceAtLeast(1))
        val rowCount = (n + c - 1) / c
        return rows(n, rowCount, "$c columns", "grid-$n-c$c")
    }

    fun heroLeft(n: Int): LayoutTemplate {
        val cells = ArrayList<FRect>()
        cells += FRect(0f, 0f, 0.6f, 1f)
        val k = n - 1
        for (i in 0 until k) cells += FRect(0.6f, i.toFloat() / k, 1f, if (i == k - 1) 1f else (i + 1f) / k)
        return LayoutTemplate("hero-left-$n", "Feature left", cells)
    }

    fun heroTop(n: Int): LayoutTemplate {
        val cells = ArrayList<FRect>()
        cells += FRect(0f, 0f, 1f, 0.58f)
        val k = n - 1
        for (i in 0 until k) cells += FRect(i.toFloat() / k, 0.58f, if (i == k - 1) 1f else (i + 1f) / k, 1f)
        return LayoutTemplate("hero-top-$n", "Feature top", cells)
    }

    /** Five-photo pinwheel with a small centre square. */
    fun pinwheel5(): LayoutTemplate = LayoutTemplate(
        "pinwheel-5", "Pinwheel",
        listOf(
            FRect(0f, 0f, 0.6f, 0.4f), FRect(0.6f, 0f, 1f, 0.6f), FRect(0.4f, 0.6f, 1f, 1f),
            FRect(0f, 0.4f, 0.4f, 1f), FRect(0.4f, 0.4f, 0.6f, 0.6f),
        ),
    )

    /** "Artistic" unequal mosaic from recursive splits; deterministic for a given [seed]. */
    fun mosaic(n: Int, seed: Int): LayoutTemplate {
        val rnd = java.util.Random(seed * 7919L + n * 104729L)
        val parts = ArrayList<FRect>()
        parts += FRect.UNIT
        var guard = 0
        while (parts.size < n && guard++ < 10_000) {
            // split a large cell: weighted towards big areas so sizes vary but none is tiny
            val idx = parts.indices.maxByOrNull { parts[it].area * (0.6f + rnd.nextFloat() * 0.8f) } ?: break
            val p = parts[idx]
            val vertical = if (abs(p.w - p.h) < 0.05f) rnd.nextBoolean() else p.w > p.h
            val ratio = 0.36f + rnd.nextFloat() * 0.28f
            val a: FRect
            val b: FRect
            if (vertical) {
                val x = p.l + p.w * ratio
                a = FRect(p.l, p.t, x, p.b); b = FRect(x, p.t, p.r, p.b)
            } else {
                val y = p.t + p.h * ratio
                a = FRect(p.l, p.t, p.r, y); b = FRect(p.l, y, p.r, p.b)
            }
            parts.removeAt(idx)
            parts += a; parts += b
        }
        val sorted = parts.sortedWith(compareBy({ Math.round(it.t * 20f) }, { it.l }))
        return LayoutTemplate("mosaic-$n-$seed", "Artistic ${seed + 1}", sorted)
    }

    /** All sensible layouts for [n] photos, best-looking defaults first. */
    fun candidates(n: Int): List<LayoutTemplate> {
        require(n >= 1) { "need at least one photo" }
        if (n == 1) return listOf(LayoutTemplate("single", "Single", listOf(FRect.UNIT)))
        val out = ArrayList<LayoutTemplate>()
        val maxRows = min(n, 8)
        val sq = Math.sqrt(n.toDouble())
        // equal-ish grids first, ordered by closeness to square
        val rowOptions = (1..maxRows).sortedBy { abs(it - sq) }
        for (r in rowOptions) {
            val name = when {
                r == 1 -> "Side by side"
                r == n -> "Stacked"
                else -> "$r rows"
            }
            out += rows(n, r, name)
        }
        if (n <= 8) {
            for (c in (2..min(n, 6)).sortedBy { abs(it - sq) }) {
                if (c == n) { out += columnsLayout(n, c, "Columns"); continue }
                out += columnsLayout(n, c, "$c columns")
            }
        }
        if (n >= 3) { out += heroLeft(n); out += heroTop(n) }
        if (n == 5) out += pinwheel5()
        if (n >= 3) for (s in 0..2) out += mosaic(n, s)
        // drop layouts that would create slivers too thin to hold a photo
        val usable = out.distinctBy { it.id }.filter { l -> l.cells.all { it.w >= MIN_CELL && it.h >= MIN_CELL } }
        return usable.ifEmpty { listOf(gridWithColumns(n, Math.ceil(sq).toInt())) }
    }

    private const val MIN_CELL = 0.07f

    private fun columnsLayout(n: Int, c: Int, name: String): LayoutTemplate {
        val counts = distribute(n, c)
        val cells = ArrayList<FRect>()
        counts.forEachIndexed { ci, k ->
            val x1 = ci.toFloat() / c
            val x2 = if (ci == c - 1) 1f else (ci + 1f) / c
            for (i in 0 until k) cells += FRect(x1, i.toFloat() / k, x2, if (i == k - 1) 1f else (i + 1f) / k)
        }
        val ordered = cells.sortedWith(compareBy({ Math.round(it.t * 100f) }, { it.l }))
        return LayoutTemplate("cols-$n-$c", name, ordered)
    }

    /** Sum over cells of |ln(cell aspect / photo aspect)|: how much cropping a layout would force. */
    fun cropCost(layout: LayoutTemplate, canvasAspect: Float, photoAspects: List<Float>): Float {
        var cost = 0f
        layout.cells.forEachIndexed { i, c ->
            val pa = photoAspects.getOrNull(i) ?: return@forEachIndexed
            val ca = c.w / c.h * canvasAspect
            cost += abs(ln(ca / pa))
        }
        return cost / layout.count
    }

    /**
     * Automatic choice: the layout + canvas ratio pair that crops the given photos least.
     * [layouts] restricts the candidate layouts (e.g. only side-by-side for comparisons).
     */
    fun auto(
        photoAspects: List<Float>,
        layouts: List<LayoutTemplate> = candidates(photoAspects.size),
        canvases: List<CanvasSpec> = CanvasSpec.PRESETS,
    ): Pair<LayoutTemplate, CanvasSpec> {
        var best: Pair<LayoutTemplate, CanvasSpec>? = null
        var bestScore = Float.MAX_VALUE
        for ((li, l) in layouts.withIndex()) for (c in canvases) {
            // small tie-breaks: prefer earlier (more regular) layouts and friendly social ratios
            val score = cropCost(l, c.aspect, photoAspects) + li * 0.004f +
                (if (c.ratioH > c.ratioW * 1.7f || c.ratioW > c.ratioH * 1.7f) 0.03f else 0f)
            if (score < bestScore) { bestScore = score; best = l to c }
        }
        return best!!
    }
}
