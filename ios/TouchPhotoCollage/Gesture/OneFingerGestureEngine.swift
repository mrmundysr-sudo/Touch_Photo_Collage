import Foundation
import CoreGraphics

/// How a touch ended up.
enum GestureOutcome: Equatable {
    /// Finger lifted without leaving the touch-slop circle. Discard any live movement; treat as a tap.
    case tap
    /// Finger held still for the long-press time. Discard any live movement; start the app's long-press action.
    case longPress
    /// The content was moved or zoomed. Commit the live state.
    case moved
}

struct GestureTuning {
    var mode: TouchMode
    var pinchEnabled: Bool
    /// Finger travel (points) that doubles the zoom.
    var pxPerDoubling: Double
    /// Soft-start distance (`GestureKnee`).
    var deadzone: Double = 4
    /// Movement over the last `stillWindow` below this means the finger is resting (long press allowed).
    var stillness: Double = 2
    /// Platform touch slop; a touch that lifts inside 3/4 of it is a tap.
    var touchSlop: Double = 8
    var longPress: TimeInterval = 0.45
    var stillWindow: TimeInterval = 0.25

    static let tapToleranceOfSlop = 0.75
}

/// Shared gesture loop of the Touch Gesture Standard, as a pure state machine fed by raw touch events. It has no UIKit
/// dependency so tests can drive it with synthetic touch sequences, and the canvas view only forwards touches to it.
///
/// Direct manipulation: movement is applied **from the first point**, every event, with no smoothing, no quantisation and
/// no animation, so the content stays under the finger. To keep taps and long presses reliable without a visible jump at
/// the touch-slop threshold, the callbacks drive *live, uncommitted* state:
///  - `onBegin` is called once, right before the first change, so the app can prepare (fetch the image, snapshot the crop);
///  - `onPan`/`onZoom` receive the exact incremental movement of this event;
///  - `onFinish` tells the app whether to commit (`.moved`) or discard (`.tap`, `.longPress`).
///
/// One finger in `.pan` pans; in `.zoom` vertical travel zooms exponentially (`OneFingerMath.zoomFactor`); two fingers (if
/// `pinchEnabled`) pinch-zoom and pan. The first `deadzone` of travel is eased in with `GestureKnee`, so there is never a step.
final class OneFingerGestureEngine {
    private enum Phase { case idle, resting, dragging, finished }

    var onBegin: () -> Void = {}
    var onPan: (CGPoint) -> Void = { _ in }
    var onZoom: (_ factor: Double, _ centroid: CGPoint?) -> Void = { _, _ in }
    var onFinish: (GestureOutcome) -> Void = { _ in }

    private var phase = Phase.idle
    private var tuning = GestureTuning(mode: .pan, pinchEnabled: true, pxPerDoubling: 160)
    private var downPos = CGPoint.zero
    private var downTime: TimeInterval = 0
    private var base = CGPoint.zero
    private var applied = CGPoint.zero
    private var dz = 4.0
    private var begun = false
    private var multi = false
    private var history: [(time: TimeInterval, pos: CGPoint)] = []
    private var active: [Int: CGPoint] = [:]
    private var previous: [Int: CGPoint] = [:]

    var isActive: Bool { phase == .resting || phase == .dragging }
    /// True once the finger has moved deliberately (or a long press was decided).
    var hasBegun: Bool { begun }
    /// Time at which `longPressTimerFired` should be called, while still undecided.
    var longPressDeadline: TimeInterval? { phase == .resting ? downTime + tuning.longPress : nil }

    func reset() {
        phase = .idle; begun = false; multi = false; history = []; active = [:]; previous = [:]; applied = .zero
    }

    // MARK: input

    func begin(id: Int, position: CGPoint, time: TimeInterval, tuning: GestureTuning) {
        reset()
        self.tuning = tuning
        phase = .resting
        downPos = position; downTime = time; base = position; dz = tuning.deadzone
        history = [(time, position)]
        active[id] = position; previous[id] = position
    }

    /// An additional finger landed.
    func fingerDown(id: Int, position: CGPoint, time: TimeInterval) {
        guard isActive else { return }
        active[id] = position; previous[id] = position
        multi = true
        if phase == .resting { phase = .dragging }
    }

    /// All currently pressed fingers' positions (only ids that are known to the engine are used).
    func moved(_ positions: [Int: CGPoint], time: TimeInterval) {
        guard isActive else { return }
        for (k, v) in positions where active[k] != nil { active[k] = v }
        if active.count >= 2 {
            multi = true
            if phase == .resting { phase = .dragging }
            pinchStep()
        } else if let pos = active.values.first {
            if phase == .resting {
                history.append((time, pos))
                applySingle(pos)
                let dist = Double(hypot(pos.x - downPos.x, pos.y - downPos.y))
                if dist > tuning.touchSlop * GestureTuning.tapToleranceOfSlop { phase = .dragging }
            } else {
                if multi { // a finger lifted: continue one-finger from here without any jump
                    multi = false; base = pos; applied = .zero; dz = 0
                } else {
                    applySingle(pos)
                }
            }
        }
        previous = active
    }

    func fingerUp(id: Int, time: TimeInterval) {
        guard isActive else { return }
        active[id] = nil
        previous[id] = nil
        if active.isEmpty {
            let outcome: GestureOutcome = phase == .resting ? .tap : .moved
            phase = .finished
            onFinish(outcome)
        }
    }

    func cancel() {
        guard isActive else { reset(); return }
        phase = .finished
        onFinish(begun ? .moved : .tap)
    }

    /// Call when `longPressDeadline` has passed. A resting finger is a long press; a finger that is still moving (a slow,
    /// careful drag) is a drag, however slowly it goes.
    func longPressTimerFired() {
        guard phase == .resting else { return }
        let end = downTime + tuning.longPress
        let cutoff = end - tuning.stillWindow
        let from = history.last(where: { $0.time <= cutoff })?.pos ?? downPos
        let last = history[history.count - 1]
        let dist = Double(hypot(last.pos.x - from.x, last.pos.y - from.y))
        let resting = dist < tuning.stillness || last.time < cutoff
        if resting {
            phase = .finished
            onFinish(.longPress)
        } else {
            phase = .dragging
        }
    }

    // MARK: movement

    private func beginIfNeeded() {
        if !begun { begun = true; onBegin() }
    }

    private func applySingle(_ pos: CGPoint) {
        let total = CGPoint(x: pos.x - base.x, y: pos.y - base.y)
        let eff: CGPoint
        switch tuning.mode {
        case .pan: eff = GestureKnee.apply(total, deadzone: dz)
        case .zoom: eff = CGPoint(x: 0, y: CGFloat(GestureKnee.applyScalar(Double(total.y), deadzone: dz)))
        }
        let d = CGPoint(x: eff.x - applied.x, y: eff.y - applied.y)
        applied = eff
        if d == .zero { return }
        beginIfNeeded()
        switch tuning.mode {
        case .pan: onPan(d)
        case .zoom: if d.y != 0 { onZoom(OneFingerMath.zoomFactor(dy: Double(d.y), pxPerDoubling: tuning.pxPerDoubling), nil) }
        }
    }

    /// Two or more fingers: pinch-zoom about the centroid and pan with it (if enabled).
    private func pinchStep() {
        guard tuning.pinchEnabled else { return }
        let ids = active.keys.filter { previous[$0] != nil }.sorted()
        guard ids.count >= 2 else { return }
        let cur = ids.compactMap { active[$0] }
        let old = ids.compactMap { previous[$0] }
        func centroid(_ pts: [CGPoint]) -> CGPoint {
            CGPoint(x: pts.map { $0.x }.reduce(0, +) / CGFloat(pts.count), y: pts.map { $0.y }.reduce(0, +) / CGFloat(pts.count))
        }
        func spread(_ pts: [CGPoint], _ c: CGPoint) -> Double {
            Double(pts.map { hypot($0.x - c.x, $0.y - c.y) }.reduce(0, +)) / Double(pts.count)
        }
        let cc = centroid(cur), oc = centroid(old)
        let cs = spread(cur, cc), os = spread(old, oc)
        let zoom = (os > 0 && cs > 0) ? cs / os : 1
        let pan = CGPoint(x: cc.x - oc.x, y: cc.y - oc.y)
        if zoom != 1 || pan != .zero {
            beginIfNeeded()
            if zoom != 1 { onZoom(zoom, cc) }
            if pan != .zero { onPan(pan) }
        }
    }
}
