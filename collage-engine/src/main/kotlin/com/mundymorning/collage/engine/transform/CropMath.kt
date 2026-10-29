package com.mundymorning.collage.engine.transform

import com.mundymorning.collage.engine.model.FRect
import kotlin.math.max
import kotlin.math.min

/**
 * Crop geometry. Everything is in normalised display-space coordinates of the photo (0..1 on both axes).
 *
 * A cell shows a "visible region" of the photo. The region always has exactly the cell's pixel aspect ratio, so
 * the photo is only ever scaled uniformly: faces and proportions are never distorted.
 *
 *  * Fill mode (cover): the region is inside the photo, the cell is completely covered, edges may be cropped.
 *  * Fit mode (contain / "avoid cropping"): at zoom 1 the region is larger than the photo and the whole photo is
 *    visible with bars; zooming in crops as in fill mode.
 */
object CropMath {
    const val MIN_ZOOM = 1f
    const val MAX_ZOOM = 8f

    data class Region(val rect: FRect, val visW: Float, val visH: Float)

    fun clampZoom(z: Float): Float = z.coerceIn(MIN_ZOOM, MAX_ZOOM)

    /** Region size at zoom 1 (normalised units). */
    fun baseSize(imgAspect: Float, cellAspect: Float, fit: Boolean): Pair<Float, Float> {
        val wide = imgAspect > cellAspect
        return if (!fit) {
            if (wide) (cellAspect / imgAspect) to 1f else 1f to (imgAspect / cellAspect)
        } else {
            if (wide) 1f to (imgAspect / cellAspect) else (cellAspect / imgAspect) to 1f
        }
    }

    fun region(imgAspect: Float, cellAspect: Float, zoom: Float, cx: Float, cy: Float, fit: Boolean): Region {
        val (bw, bh) = baseSize(imgAspect, cellAspect, fit)
        val z = clampZoom(zoom)
        val vw = bw / z
        val vh = bh / z
        val ccx = clampCenter(cx, vw)
        val ccy = clampCenter(cy, vh)
        return Region(FRect(ccx - vw / 2f, ccy - vh / 2f, ccx + vw / 2f, ccy + vh / 2f), vw, vh)
    }

    /** Keep the region inside the photo; if it is larger than the photo (fit mode) it stays centred. */
    fun clampCenter(c: Float, vis: Float): Float =
        if (vis >= 1f) 0.5f else c.coerceIn(vis / 2f, 1f - vis / 2f)

    /** Part of the photo inside the region (null if disjoint, which cannot happen for valid input). */
    fun photoPart(region: Region): FRect = region.rect.intersect(FRect.UNIT) ?: FRect.UNIT

    /** Where [photoPart] lands inside the cell rectangle [cell] (pixels). */
    fun destRect(region: Region, cell: FRect): FRect {
        val p = photoPart(region)
        val sx = cell.w / region.visW
        val sy = cell.h / region.visH
        return FRect(
            cell.l + (p.l - region.rect.l) * sx,
            cell.t + (p.t - region.rect.t) * sy,
            cell.l + (p.r - region.rect.l) * sx,
            cell.t + (p.b - region.rect.t) * sy,
        )
    }

    /** Result of dragging the photo by [dxPx]/[dyPx] screen pixels inside a cell of [cellW] x [cellH] pixels. */
    fun pan(
        imgAspect: Float, cellW: Float, cellH: Float, zoom: Float, cx: Float, cy: Float, fit: Boolean,
        dxPx: Float, dyPx: Float,
    ): Pair<Float, Float> {
        val r = region(imgAspect, cellW / cellH, zoom, cx, cy, fit)
        val ncx = clampCenter(r.rect.cx - dxPx / cellW * r.visW, r.visW)
        val ncy = clampCenter(r.rect.cy - dyPx / cellH * r.visH, r.visH)
        return ncx to ncy
    }

    /**
     * Zoom about a screen point so the photo content under the fingers stays put.
     * [fx]/[fy] are the focal point within the cell, 0..1.
     */
    fun zoomAbout(
        imgAspect: Float, cellAspect: Float, zoom: Float, cx: Float, cy: Float, fit: Boolean,
        newZoom: Float, fx: Float, fy: Float,
    ): Triple<Float, Float, Float> {
        val r = region(imgAspect, cellAspect, zoom, cx, cy, fit)
        val z2 = clampZoom(newZoom)
        val (bw, bh) = baseSize(imgAspect, cellAspect, fit)
        val vw2 = bw / z2
        val vh2 = bh / z2
        val px = r.rect.l + fx * r.visW
        val py = r.rect.t + fy * r.visH
        val ncx = clampCenter(px - (fx - 0.5f) * vw2, vw2)
        val ncy = clampCenter(py - (fy - 0.5f) * vh2, vh2)
        return Triple(z2, ncx, ncy)
    }

    /** Largest power-of-two decode sample so the decoded image still has at least the needed resolution. */
    fun sampleFor(destPxPerSourcePx: Float): Int {
        if (destPxPerSourcePx <= 0f || destPxPerSourcePx >= 1f) return 1
        var s = 1
        while (2 * s <= 1f / destPxPerSourcePx && s < 64) s *= 2
        return max(1, min(64, s))
    }
}
