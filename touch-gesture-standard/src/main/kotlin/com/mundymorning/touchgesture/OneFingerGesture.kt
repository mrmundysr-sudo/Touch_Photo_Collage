package com.mundymorning.touchgesture

import androidx.compose.foundation.gestures.calculateCentroid
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.AwaitPointerEventScope
import androidx.compose.ui.input.pointer.positionChange
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Shared gesture loop of the Touch Gesture Standard. Call it from `awaitEachGesture` after the first finger is
 * down (and after any long-press handling the app does itself); it returns when all fingers are lifted.
 *
 *  - one finger in [TouchMode.PAN]  -> [onPan] with the finger's movement in pixels
 *  - one finger in [TouchMode.ZOOM] -> [onZoom] with an exponential factor from vertical movement, `centroid = null`
 *  - two fingers (if [pinchEnabled]) -> pinch zoom and pan, `centroid` = the pinch centre
 *
 * @return true if the content was moved or zoomed.
 */
suspend fun AwaitPointerEventScope.oneFingerOrPinchGesture(
    mode: TouchMode,
    pinchEnabled: Boolean,
    pxPerDoubling: Float,
    onPan: (Offset) -> Unit,
    onZoom: (factor: Float, centroid: Offset?) -> Unit,
    /** Finger travel already observed before this loop started (e.g. while deciding it was not a long press). */
    initialDelta: Offset = Offset.Zero,
): Boolean {
    var moved = false
    if (initialDelta != Offset.Zero) {
        when (mode) {
            TouchMode.PAN -> onPan(initialDelta)
            TouchMode.ZOOM -> if (initialDelta.y != 0f) onZoom(OneFingerMath.zoomFactor(initialDelta.y, pxPerDoubling), null)
        }
        moved = true
    }
    do {
        val event = awaitPointerEvent()
        val down = event.changes.filter { it.pressed }
        if (down.size >= 2) {
            if (pinchEnabled) {
                val zoom = event.calculateZoom()
                val pan = event.calculatePan()
                if (zoom != 1f) onZoom(zoom, event.calculateCentroid(useCurrent = true))
                if (pan != Offset.Zero) onPan(pan)
                if (zoom != 1f || pan != Offset.Zero) { moved = true; event.changes.forEach { if (it.pressed) it.consume() } }
            }
        } else if (down.size == 1) {
            val ch = down[0]
            val d = ch.positionChange()
            if (d != Offset.Zero) {
                when (mode) {
                    TouchMode.PAN -> onPan(d)
                    TouchMode.ZOOM -> if (d.y != 0f) onZoom(OneFingerMath.zoomFactor(d.y, pxPerDoubling), null)
                }
                moved = true
                ch.consume()
            }
        }
    } while (event.changes.any { it.pressed })
    return moved
}

/** What the first moments of a touch turned out to be. */
enum class TouchStart { TAP, LONG_PRESS, MOVE, MULTI_TOUCH }

/**
 * Decides, right after a finger lands, whether it is a tap, a long press (held still for the system long-press time),
 * the start of a drag (moved past touch slop) or the start of a multi-finger gesture. Movement is detected
 * immediately, so dragging never waits for the long-press timeout.
 *
 * @param delta travel from the touch-down point at the moment [TouchStart.MOVE] was detected.
 */
suspend fun AwaitPointerEventScope.classifyTouchStart(
    down: androidx.compose.ui.input.pointer.PointerInputChange,
    onDelta: (Offset) -> Unit = {},
): TouchStart {
    var delta = Offset.Zero
    val result = withTimeoutOrNull(viewConfiguration.longPressTimeoutMillis) {
        var out = TouchStart.TAP
        while (true) {
            val ev = awaitPointerEvent()
            val ch = ev.changes.firstOrNull { it.id == down.id } ?: return@withTimeoutOrNull TouchStart.TAP
            if (ev.changes.count { it.pressed } > 1) { out = TouchStart.MULTI_TOUCH; break }
            if (!ch.pressed) { out = TouchStart.TAP; break }
            val d = ch.position - down.position
            if (d.getDistance() > viewConfiguration.touchSlop) { delta = d; out = TouchStart.MOVE; break }
        }
        out
    }
    onDelta(delta)
    return result ?: TouchStart.LONG_PRESS
}
