package com.mundymorning.touchphotocollage

import android.graphics.Bitmap
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.mundymorning.collage.engine.transform.CropMath

/**
 * Uncommitted, per-frame crop of the photo under the finger.
 *
 * While a finger is down the project is NOT modified: this holder owns the crop in full floating-point precision and
 * the canvas draws it directly on the GPU from an already decoded bitmap. The numbers are Compose state read only in
 * the draw phase, so each touch event costs one cheap redraw: no project copy, no re-render, no decode, no
 * recomposition and no save. On release the final crop is committed once (one undo step).
 */
class LiveGesture {
    var active by mutableStateOf(false); private set
    var index by mutableIntStateOf(-1); private set
    var zoom by mutableFloatStateOf(1f); private set
    var cx by mutableFloatStateOf(0.5f); private set
    var cy by mutableFloatStateOf(0.5f); private set

    /** Committed to the project, waiting for the re-rendered frame before the live layer is removed. */
    var commitPending by mutableStateOf(false); private set
    var bitmap: Bitmap? = null; private set

    fun begin(i: Int, zoom: Float, cx: Float, cy: Float, bmp: Bitmap) {
        index = i; this.zoom = zoom; this.cx = cx; this.cy = cy; bitmap = bmp; commitPending = false; active = true
    }

    /** Drag the photo by [dxPx]/[dyPx] screen pixels inside a cell of [cellW] x [cellH] pixels. */
    fun pan(dxPx: Float, dyPx: Float, imgAspect: Float, cellW: Float, cellH: Float, fit: Boolean) {
        val (nx, ny) = CropMath.pan(imgAspect, cellW, cellH, zoom, cx, cy, fit, dxPx, dyPx)
        cx = nx; cy = ny
    }

    /** Multiply the zoom by [factor] about the point ([fx], [fy]) of the cell (0..1). */
    fun zoomBy(factor: Float, fx: Float, fy: Float, imgAspect: Float, cellAspect: Float, fit: Boolean) {
        val (z, nx, ny) = CropMath.zoomAbout(imgAspect, cellAspect, zoom, cx, cy, fit, zoom * factor, fx, fy)
        zoom = z; cx = nx; cy = ny
    }

    fun markCommitted() { commitPending = true }

    /** Drop the live layer (tap, long press, or the committed frame is on screen). */
    fun clear() { active = false; commitPending = false; bitmap = null }
}
