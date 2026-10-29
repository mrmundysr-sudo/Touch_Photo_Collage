package com.mundymorning.touchgesture

import android.content.SharedPreferences
import kotlin.math.ln
import kotlin.math.pow

/**
 * Touch Gesture Standard (Mundy Morning Studios), v1.
 *
 * Wherever an app lets the user zoom or pan content, it must also offer one-finger alternatives:
 *  - a visible mode switch with two modes, [TouchMode.PAN] and [TouchMode.ZOOM];
 *  - PAN: one finger drags the content in any direction;
 *  - ZOOM: one finger slides up to zoom in and down to zoom out, proportionally (no thresholds or steps);
 *  - a RESET button that restores the automatic/starting view;
 *  - pinch (two fingers) stays available as an option the user can turn off;
 *  - the active mode is always shown in words, and the choice is remembered between sessions.
 * Apps must NOT apply this to gestures that already carry gameplay meaning.
 */
enum class TouchMode { PAN, ZOOM }

object OneFingerMath {
    /** Finger travel (dp) that doubles or halves the zoom. Small movements give small, smooth changes. */
    const val DEFAULT_DP_PER_DOUBLING = 160f

    /**
     * Zoom factor for a finger movement of [dyPx] pixels (screen y grows downwards).
     * Sliding up (negative dy) zooms in (>1), down zooms out (<1). Exponential, so equal movements always give
     * equal ratios: perfectly proportional and reversible (up then the same distance down returns to the start).
     */
    fun zoomFactor(dyPx: Float, pxPerDoubling: Float): Float {
        require(pxPerDoubling > 0f) { "pxPerDoubling must be positive" }
        return 2.0.pow((-dyPx / pxPerDoubling).toDouble()).toFloat()
    }

    /** Inverse: finger travel for a zoom ratio. */
    fun travelFor(factor: Float, pxPerDoubling: Float): Float = (-ln(factor.toDouble()) / ln(2.0) * pxPerDoubling).toFloat()

    fun clampZoom(current: Float, factor: Float, min: Float, max: Float): Float = (current * factor).coerceIn(min, max)
}

/** Persists the user's gesture preferences. Uses a caller-supplied [SharedPreferences] (no extra permissions). */
class GestureSettings(private val prefs: SharedPreferences) {
    var mode: TouchMode
        get() = runCatching { TouchMode.valueOf(prefs.getString(KEY_MODE, null) ?: "") }.getOrDefault(TouchMode.PAN)
        set(v) { prefs.edit().putString(KEY_MODE, v.name).apply() }

    /** Two-finger pinch zoom enabled (default on). */
    var pinchEnabled: Boolean
        get() = prefs.getBoolean(KEY_PINCH, true)
        set(v) { prefs.edit().putBoolean(KEY_PINCH, v).apply() }

    var introSeen: Boolean
        get() = prefs.getBoolean(KEY_INTRO, false)
        set(v) { prefs.edit().putBoolean(KEY_INTRO, v).apply() }

    private companion object {
        const val KEY_MODE = "touch_gesture_mode"
        const val KEY_PINCH = "touch_gesture_pinch"
        const val KEY_INTRO = "touch_gesture_intro_seen"
    }
}
