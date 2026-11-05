import Foundation
import CoreGraphics

/// Touch Gesture Standard (Mundy Morning Studios), v1.1: Swift port of the Android `touch-gesture-standard` module.
///
/// Wherever an app lets the user zoom or pan content, it also offers one-finger alternatives:
///  - a visible mode switch with two modes, `.pan` and `.zoom`;
///  - PAN: one finger drags the content in any direction;
///  - ZOOM: one finger slides up to zoom in and down to zoom out, proportionally (no thresholds or steps);
///  - a RESET button that restores the automatic/starting view;
///  - pinch (two fingers) stays available as an option the user can turn off;
///  - the active mode is always shown in words, and the choice is remembered between sessions.
enum TouchMode: String {
    case pan = "PAN", zoom = "ZOOM"

    var label: String { rawValue }
    var glyph: String { self == .pan ? "✥" : "⇕" }

    /// Text that tells the user, in words, what one finger will do right now.
    func instruction(hasTarget: Bool = true) -> String {
        if !hasTarget { return "Tap a photo to choose it" }
        return self == .pan ? "PAN: drag one finger to move the photo" : "ZOOM: slide one finger up to zoom in, down to zoom out"
    }
}

enum OneFingerMath {
    /// Finger travel (points) that doubles or halves the zoom. Small movements give small, smooth changes.
    static let defaultPtPerDoubling = 160.0

    /// Zoom factor for a finger movement of `dy` points (screen y grows downwards). Sliding up (negative dy) zooms in
    /// (>1), down zooms out (<1). Exponential, so equal movements always give equal ratios: perfectly proportional and
    /// reversible (up then the same distance down returns to the start).
    static func zoomFactor(dy: Double, pxPerDoubling: Double) -> Double {
        precondition(pxPerDoubling > 0, "pxPerDoubling must be positive")
        return pow(2.0, -dy / pxPerDoubling)
    }

    /// Inverse: finger travel for a zoom ratio.
    static func travelFor(factor: Double, pxPerDoubling: Double) -> Double { -log(factor) / log(2.0) * pxPerDoubling }

    static let sensitivityMin = 0.25
    static let sensitivityMax = 3.0
    static let sensitivityDefault = 1.0
    static let sensitivityFine = 0.4

    static func clampSensitivity(_ s: Double) -> Double { min(max(s, sensitivityMin), sensitivityMax) }

    /// Finger travel in points that doubles the zoom, for a display `density` and a user `sensitivity`.
    static func pxPerDoubling(density: Double, sensitivity: Double) -> Double {
        defaultPtPerDoubling * density / clampSensitivity(sensitivity)
    }

    /// Slider position 0...1 <-> sensitivity on a logarithmic scale, so the fine end gets as much room as the fast end.
    static func sensitivityFromSlider(_ t: Double) -> Double {
        sensitivityMin * pow(sensitivityMax / sensitivityMin, min(max(t, 0), 1))
    }

    static func sliderFromSensitivity(_ s: Double) -> Double {
        log(clampSensitivity(s) / sensitivityMin) / log(sensitivityMax / sensitivityMin)
    }

    static func clampZoom(current: Double, factor: Double, min lo: Double, max hi: Double) -> Double { Swift.min(Swift.max(current * factor, lo), hi) }
}

/// Soft start for one-finger movement. Instead of ignoring the first few points (a dead zone that then "jumps"),
/// movement inside `deadzone` is scaled by `|v| / deadzone`, which is 0 at the touch point and exactly 1 at the edge.
/// The result is continuous (no step when the threshold is crossed), never lags the finger by more than `deadzone / 4`,
/// and filters out the few points of tremor of a finger that is merely resting.
enum GestureKnee {
    static func apply(_ v: CGPoint, deadzone: Double) -> CGPoint {
        if deadzone <= 0 { return v }
        let m = Double(hypot(v.x, v.y))
        if m >= deadzone { return v }
        let k = CGFloat(m / deadzone)
        return CGPoint(x: v.x * k, y: v.y * k)
    }

    static func applyScalar(_ v: Double, deadzone: Double) -> Double {
        if deadzone <= 0 { return v }
        let m = abs(v)
        return m >= deadzone ? v : v * (m / deadzone)
    }
}

/// Persists the user's gesture preferences (no extra permissions). Keys match the Android app.
final class GestureSettings {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private enum Key {
        static let mode = "touch_gesture_mode"
        static let pinch = "touch_gesture_pinch"
        static let sens = "touch_gesture_zoom_sensitivity"
        static let frames = "touch_gesture_frame_timing"
        static let intro = "touch_gesture_intro_seen"
    }

    var mode: TouchMode {
        get { defaults.string(forKey: Key.mode).flatMap(TouchMode.init(rawValue:)) ?? .pan }
        set { defaults.set(newValue.rawValue, forKey: Key.mode) }
    }

    /// Two-finger pinch zoom enabled (default on).
    var pinchEnabled: Bool {
        get { defaults.object(forKey: Key.pinch) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.pinch) }
    }

    var zoomSensitivity: Double {
        get { OneFingerMath.clampSensitivity(defaults.object(forKey: Key.sens) as? Double ?? OneFingerMath.sensitivityDefault) }
        set { defaults.set(OneFingerMath.clampSensitivity(newValue), forKey: Key.sens) }
    }

    /// Developer/testing aid: show a live frame-timing readout.
    var showFrameTiming: Bool {
        get { defaults.object(forKey: Key.frames) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.frames) }
    }

    var introSeen: Bool {
        get { defaults.object(forKey: Key.intro) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.intro) }
    }
}

/// Rolling frame statistics over a time window. Pure, unit-tested.
final class FrameStats {
    private let windowNanos: Int64
    private let jankNanos: Int64
    private var times: [Int64] = []
    private var durations: [Int64] = []
    private var last: Int64 = 0

    init(windowNanos: Int64 = 1_000_000_000, jankNanos: Int64 = 20_000_000) {
        self.windowNanos = windowNanos; self.jankNanos = jankNanos
    }

    /// Record a frame presented at `nowNanos`.
    func record(_ nowNanos: Int64) {
        if last != 0 { times.append(nowNanos); durations.append(nowNanos - last) }
        last = nowNanos
        while let first = times.first, nowNanos - first > windowNanos { times.removeFirst(); durations.removeFirst() }
    }

    var frames: Int { durations.count }
    var avgMs: Double { durations.isEmpty ? 0 : Double(durations.reduce(0, +)) / Double(durations.count) / 1e6 }
    var worstMs: Double { Double(durations.max() ?? 0) / 1e6 }
    var jankyFrames: Int { durations.filter { $0 > jankNanos }.count }
    var fps: Double { durations.isEmpty ? 0 : 1e9 / (Double(durations.reduce(0, +)) / Double(durations.count)) }

    func summary() -> String {
        frames == 0 ? "frames: …" : String(format: "%.0f fps · avg %.1f ms · worst %.0f ms · janky %d", fps, avgMs, worstMs, jankyFrames)
    }

    func reset() { times.removeAll(); durations.removeAll(); last = 0 }
}
