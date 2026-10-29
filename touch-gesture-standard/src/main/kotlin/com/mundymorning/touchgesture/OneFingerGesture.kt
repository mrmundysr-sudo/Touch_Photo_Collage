package com.mundymorning.touchgesture

import androidx.compose.foundation.gestures.calculateCentroid
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.AwaitPointerEventScope
import androidx.compose.ui.input.pointer.PointerInputChange
import kotlinx.coroutines.withTimeoutOrNull

/** How a touch ended up. */
enum class GestureOutcome {
    /** Finger lifted without leaving the touch-slop circle. Discard any live movement; treat as a tap. */
    TAP,

    /** Finger held still for the system long-press time. Discard any live movement; start the app's long-press action. */
    LONG_PRESS,

    /** The content was moved or zoomed. Commit the live state. */
    MOVED,
}

/**
 * Shared gesture loop of the Touch Gesture Standard. Call it from `awaitEachGesture` right after `awaitFirstDown`.
 *
 * Direct manipulation: movement is applied **from the first pixel**, every event, with no smoothing, no
 * quantisation and no animation, so the content stays under the finger. To keep taps and long-presses reliable
 * without a visible jump at the touch-slop threshold, the callbacks are meant to drive *live, uncommitted* state:
 *  - [onBegin] is called once, right before the first change, so the app can prepare (fetch the bitmap, snapshot the crop);
 *  - [onPan]/[onZoom] are called with the exact incremental movement of this event;
 *  - the result tells the app whether to commit ([GestureOutcome.MOVED]) or discard ([TAP], [LONG_PRESS]).
 *
 * One finger in [TouchMode.PAN] pans; in [TouchMode.ZOOM] vertical travel zooms exponentially
 * (see [OneFingerMath.zoomFactor]); two fingers (if [pinchEnabled]) pinch-zoom and pan. The first [deadzonePx] of
 * travel is eased in with [GestureKnee] so there is never a step.
 */
/** Fraction of the platform touch slop within which a finger still counts as resting. */
const val TAP_TOLERANCE_OF_SLOP = 0.75f

/** A long press needs the finger to have moved less than the stillness distance during this final window. */
const val STILL_WINDOW_MS = 250L

suspend fun AwaitPointerEventScope.touchGesture(
    down: PointerInputChange,
    mode: TouchMode,
    pinchEnabled: Boolean,
    pxPerDoubling: Float,
    deadzonePx: Float,
    /** Movement over the last [STILL_WINDOW_MS] below this means the finger is resting (long press allowed). */
    stillnessPx: Float,
    onBegin: () -> Unit,
    onPan: (Offset) -> Unit,
    onZoom: (factor: Float, centroid: Offset?) -> Unit,
): GestureOutcome {
    var begun = false
    var base = down.position
    var applied = Offset.Zero           // effective one-finger travel already delivered to the callbacks
    var dz = deadzonePx
    fun begin() { if (!begun) { begun = true; onBegin() } }

    fun applySingle(pos: Offset) {
        val total = pos - base
        val eff = when (mode) {
            TouchMode.PAN -> GestureKnee.apply(total, dz)
            TouchMode.ZOOM -> Offset(0f, GestureKnee.applyScalar(total.y, dz))
        }
        val d = eff - applied
        applied = eff
        if (d == Offset.Zero) return
        begin()
        when (mode) {
            TouchMode.PAN -> onPan(d)
            TouchMode.ZOOM -> if (d.y != 0f) onZoom(OneFingerMath.zoomFactor(d.y, pxPerDoubling), null)
        }
    }

    // Phase 1: until the finger moves deliberately (or lifts, or a second finger lands, or the long-press time passes).
    // Tap tolerance is 3/4 of the platform slop, so resting tremor still reads as a tap and nothing is committed.
    val slop = viewConfiguration.touchSlop * TAP_TOLERANCE_OF_SLOP
    val longPressMs = viewConfiguration.longPressTimeoutMillis
    val history = ArrayList<Pair<Long, Offset>>()
    history += down.uptimeMillis to down.position
    var multi = false
    val phase1 = withTimeoutOrNull(longPressMs) {
        var result = 0 // 1 = lifted, 2 = left the tap circle, 3 = second finger
        while (result == 0) {
            val ev = awaitPointerEvent()
            val pressed = ev.changes.filter { it.pressed }
            val ch = ev.changes.firstOrNull { it.id == down.id }
            when {
                pressed.size >= 2 -> result = 3
                ch == null || !ch.pressed -> result = 1
                else -> {
                    history += ch.uptimeMillis to ch.position
                    applySingle(ch.position)
                    if (ch.position != ch.previousPosition && begun) ch.consume()
                    if ((ch.position - down.position).getDistance() > slop) result = 2
                }
            }
        }
        result
    }
    if (phase1 == null) {
        // Long-press time elapsed without leaving the tap circle. A resting finger is a long press; a finger that is
        // still moving (a slow, careful drag) is a drag, however slowly it goes.
        val end = down.uptimeMillis + longPressMs
        val from = history.lastOrNull { it.first <= end - STILL_WINDOW_MS }?.second ?: down.position
        val to = history.last().second
        val resting = (to - from).getDistance() < stillnessPx || history.last().first < end - STILL_WINDOW_MS
        if (resting) return GestureOutcome.LONG_PRESS
    } else if (phase1 == 1) {
        return GestureOutcome.TAP
    }
    multi = phase1 == 3

    // Phase 2: a committed drag or pinch. Slop no longer matters, so there is no delay of any kind.
    do {
        val ev = awaitPointerEvent()
        val pressed = ev.changes.filter { it.pressed }
        if (pressed.size >= 2) {
            multi = true
            if (pinchEnabled) {
                val zoom = ev.calculateZoom()
                val pan = ev.calculatePan()
                if (zoom != 1f || pan != Offset.Zero) {
                    begin()
                    if (zoom != 1f) onZoom(zoom, ev.calculateCentroid(useCurrent = true))
                    if (pan != Offset.Zero) onPan(pan)
                    pressed.forEach { it.consume() }
                }
            }
        } else if (pressed.size == 1) {
            val ch = pressed[0]
            if (multi) { // a finger lifted: continue one-finger from here without any jump
                multi = false; base = ch.position; applied = Offset.Zero; dz = 0f
            } else {
                applySingle(ch.position)
                if (ch.position != ch.previousPosition) ch.consume()
            }
        }
    } while (ev.changes.any { it.pressed })
    return GestureOutcome.MOVED
}
