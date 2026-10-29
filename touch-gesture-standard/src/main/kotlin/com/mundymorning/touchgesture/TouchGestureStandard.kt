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

    /** Sensitivity bounds. 1.0 = [DEFAULT_DP_PER_DOUBLING]; higher zooms faster, lower gives finer control. */
    const val SENSITIVITY_MIN = 0.25f
    const val SENSITIVITY_MAX = 3.0f
    const val SENSITIVITY_DEFAULT = 1.0f
    const val SENSITIVITY_FINE = 0.4f

    fun clampSensitivity(s: Float): Float = s.coerceIn(SENSITIVITY_MIN, SENSITIVITY_MAX)

    /** Finger travel in pixels that doubles the zoom, for a display [density] and a user [sensitivity]. */
    fun pxPerDoubling(density: Float, sensitivity: Float): Float =
        DEFAULT_DP_PER_DOUBLING * density / clampSensitivity(sensitivity)

    /** Slider position 0..1 <-> sensitivity on a logarithmic scale, so the fine end gets as much room as the fast end. */
    fun sensitivityFromSlider(t: Float): Float =
        SENSITIVITY_MIN * (SENSITIVITY_MAX / SENSITIVITY_MIN).toDouble().pow(t.coerceIn(0f, 1f).toDouble()).toFloat()

    fun sliderFromSensitivity(s: Float): Float =
        (ln(clampSensitivity(s) / SENSITIVITY_MIN.toDouble()) / ln((SENSITIVITY_MAX / SENSITIVITY_MIN).toDouble())).toFloat()

    fun clampZoom(current: Float, factor: Float, min: Float, max: Float): Float = (current * factor).coerceIn(min, max)
}

/**
 * Soft start for one-finger movement. Instead of ignoring the first few pixels (a dead zone that then "jumps"),
 * movement inside [deadzonePx] is scaled by `|v| / deadzonePx`, which is 0 at the touch point and exactly 1 at the
 * edge. The result is continuous (no step when the threshold is crossed), never lags the finger by more than
 * `deadzonePx / 4`, and filters out the few pixels of tremor of a finger that is merely resting.
 */
object GestureKnee {
    fun apply(v: androidx.compose.ui.geometry.Offset, deadzonePx: Float): androidx.compose.ui.geometry.Offset {
        if (deadzonePx <= 0f) return v
        val m = v.getDistance()
        return if (m >= deadzonePx) v else v * (m / deadzonePx)
    }

    fun applyScalar(v: Float, deadzonePx: Float): Float {
        if (deadzonePx <= 0f) return v
        val m = kotlin.math.abs(v)
        return if (m >= deadzonePx) v else v * (m / deadzonePx)
    }
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

    /** Zoom sensitivity multiplier, see [OneFingerMath.SENSITIVITY_DEFAULT]. */
    var zoomSensitivity: Float
        get() = OneFingerMath.clampSensitivity(prefs.getFloat(KEY_SENS, OneFingerMath.SENSITIVITY_DEFAULT))
        set(v) { prefs.edit().putFloat(KEY_SENS, OneFingerMath.clampSensitivity(v)).apply() }

    /** Developer/testing aid: show a live frame-timing readout. */
    var showFrameTiming: Boolean
        get() = prefs.getBoolean(KEY_FRAMES, false)
        set(v) { prefs.edit().putBoolean(KEY_FRAMES, v).apply() }

    var introSeen: Boolean
        get() = prefs.getBoolean(KEY_INTRO, false)
        set(v) { prefs.edit().putBoolean(KEY_INTRO, v).apply() }

    private companion object {
        const val KEY_MODE = "touch_gesture_mode"
        const val KEY_PINCH = "touch_gesture_pinch"
        const val KEY_SENS = "touch_gesture_zoom_sensitivity"
        const val KEY_FRAMES = "touch_gesture_frame_timing"
        const val KEY_INTRO = "touch_gesture_intro_seen"
    }
}
