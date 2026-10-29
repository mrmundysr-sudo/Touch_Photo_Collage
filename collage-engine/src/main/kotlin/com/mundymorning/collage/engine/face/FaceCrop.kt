package com.mundymorning.collage.engine.face

import com.mundymorning.collage.engine.model.FRect
import com.mundymorning.collage.engine.transform.CropMath
import kotlin.math.max
import kotlin.math.min

/** Crop state for one cell (display space). */
data class CropState(val zoom: Float, val cx: Float, val cy: Float)

/** One photo as seen by the face-aware crop logic. */
data class FaceInput(
    /** Aspect (w/h) of the *display* image. */
    val imgAspect: Float,
    /** Faces in display space, normalised. Empty = none found, crop falls back to the centre. */
    val faces: List<FRect>,
    /** Pixel aspect of the cell the photo will fill. */
    val cellAspect: Float,
    val fit: Boolean = false,
)

/**
 * Face-aware crop planning. Pure maths, no ML: detection is done elsewhere and only boxes arrive here.
 * Zoom is always uniform (the visible region keeps the cell's aspect ratio), so faces are never distorted.
 */
object FaceCrop {
    /** Vertical position of the face centre inside the cell that looks natural for portraits. */
    const val TARGET_Y = 0.40f
    const val DESIRED_FACE_HEIGHT = 0.34f
    private const val MAX_ALIGN_ZOOM = 6f

    /** Largest face by area (the subject). */
    fun primary(faces: List<FRect>): FRect? = faces.maxByOrNull { it.area }

    /** Smallest crop that keeps every face visible: just centre on the faces, zoom 1. */
    fun smart(input: FaceInput): CropState {
        if (input.faces.isEmpty() || input.fit) return CropState(1f, 0.5f, 0.5f)
        val all = input.faces.reduce { a, b -> a.union(b) }
        val region = CropMath.region(input.imgAspect, input.cellAspect, 1f, 0.5f, 0.5f, false)
        // put the subject slightly above centre if there is room vertically
        val cy = if (region.visH < 1f) all.cy + (0.5f - TARGET_Y) * region.visH else 0.5f
        val cx = all.cx
        // zoom in a little for a single close subject only when it would stay comfortably in frame
        return clampState(input, CropState(1f, cx, cy))
    }

    /** Fraction of the cell height the main face occupies at zoom 1. */
    fun naturalFaceHeight(input: FaceInput): Float? {
        val f = primary(input.faces) ?: return null
        val region = CropMath.region(input.imgAspect, input.cellAspect, 1f, 0.5f, 0.5f, input.fit)
        return f.h / region.visH
    }

    /**
     * Align several photos so their main faces have (nearly) the same size and sit at the same height.
     * Photos without a face keep a centre crop. Returns one [CropState] per input.
     */
    fun align(inputs: List<FaceInput>): List<CropState> {
        val natural = inputs.map { if (it.fit) null else naturalFaceHeight(it) }
        val known = natural.filterNotNull()
        if (known.isEmpty()) return inputs.map { CropState(1f, 0.5f, 0.5f) }
        // The shared face height must be reachable (zoom >= 1) for every photo and not need absurd zoom.
        val lo = known.max()
        val hi = known.min() * MAX_ALIGN_ZOOM
        val target = if (lo > hi) lo else DESIRED_FACE_HEIGHT.coerceIn(lo, hi)
        return inputs.mapIndexed { i, input ->
            val nat = natural[i]
            val face = primary(input.faces)
            if (nat == null || face == null) {
                if (input.faces.isEmpty()) CropState(1f, 0.5f, 0.5f) else smart(input)
            } else {
                val zoom = (target / nat).coerceIn(1f, MAX_ALIGN_ZOOM)
                val region = CropMath.region(input.imgAspect, input.cellAspect, zoom, 0.5f, 0.5f, false)
                // face centre should land at TARGET_Y of the cell height
                val cy = face.cy + (0.5f - TARGET_Y) * region.visH
                clampState(input, CropState(zoom, face.cx, cy))
            }
        }
    }

    private fun clampState(input: FaceInput, s: CropState): CropState {
        val r = CropMath.region(input.imgAspect, input.cellAspect, s.zoom, s.cx, s.cy, input.fit)
        return CropState(CropMath.clampZoom(s.zoom), r.rect.cx, r.rect.cy)
    }

    /** True if [faces] lie fully inside the region described by [state]. */
    fun facesVisible(input: FaceInput, state: CropState): Boolean {
        val r = CropMath.region(input.imgAspect, input.cellAspect, state.zoom, state.cx, state.cy, input.fit).rect
        return input.faces.all { f -> f.l >= r.l - 1e-4f && f.r <= r.r + 1e-4f && f.t >= r.t - 1e-4f && f.b <= r.b + 1e-4f }
    }

    @Suppress("unused")
    private fun spread(a: Float, b: Float) = max(a, b) - min(a, b)
}
