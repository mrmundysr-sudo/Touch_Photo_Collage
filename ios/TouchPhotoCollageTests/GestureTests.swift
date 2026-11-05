import XCTest
@testable import TouchPhotoCollage

final class OneFingerMathTests: XCTestCase {
    func testSlidingUpZoomsInAndDownZoomsOut() {
        XCTAssertGreaterThan(OneFingerMath.zoomFactor(dy: -50, pxPerDoubling: 160), 1)
        XCTAssertLessThan(OneFingerMath.zoomFactor(dy: 50, pxPerDoubling: 160), 1)
        XCTAssertEqual(OneFingerMath.zoomFactor(dy: 0, pxPerDoubling: 160), 1)
    }

    func testOneDoublingDistanceDoublesAndHalves() {
        XCTAssertEqual(OneFingerMath.zoomFactor(dy: -160, pxPerDoubling: 160), 2, accuracy: 1e-12)
        XCTAssertEqual(OneFingerMath.zoomFactor(dy: 160, pxPerDoubling: 160), 0.5, accuracy: 1e-12)
    }

    func testIsProportionalAndReversible() {
        let up = OneFingerMath.zoomFactor(dy: -37.3, pxPerDoubling: 160)
        let down = OneFingerMath.zoomFactor(dy: 37.3, pxPerDoubling: 160)
        XCTAssertEqual(up * down, 1, accuracy: 1e-12)
        XCTAssertEqual(OneFingerMath.zoomFactor(dy: -20, pxPerDoubling: 160) * OneFingerMath.zoomFactor(dy: -20, pxPerDoubling: 160),
                       OneFingerMath.zoomFactor(dy: -40, pxPerDoubling: 160), accuracy: 1e-12, "equal movements give equal ratios")
    }

    func testTravelIsTheInverseOfFactor() {
        for f in [0.25, 0.7, 1.0, 1.9, 6.0] {
            let t = OneFingerMath.travelFor(factor: f, pxPerDoubling: 160)
            XCTAssertEqual(OneFingerMath.zoomFactor(dy: t, pxPerDoubling: 160), f, accuracy: 1e-9, "travel is the finger's dy that produces the factor")
        }
    }

    func testZoomIsClampedToLimits() {
        XCTAssertEqual(OneFingerMath.clampZoom(current: 1, factor: 0.1, min: 1, max: 8), 1)
        XCTAssertEqual(OneFingerMath.clampZoom(current: 4, factor: 10, min: 1, max: 8), 8)
    }

    func testInstructionAlwaysNamesTheMode() {
        XCTAssertTrue(TouchMode.pan.instruction().hasPrefix("PAN"))
        XCTAssertTrue(TouchMode.zoom.instruction().hasPrefix("ZOOM"))
        XCTAssertTrue(TouchMode.zoom.instruction(hasTarget: false).lowercased().contains("tap a photo"))
    }

    func testKneeIsContinuousAcrossTheThresholdAndIdentityBeyondIt() {
        let dz = 4.0
        let below = GestureKnee.apply(CGPoint(x: 3.999999, y: 0), deadzone: dz)
        let at = GestureKnee.apply(CGPoint(x: 4, y: 0), deadzone: dz)
        XCTAssertEqual(Double(below.x), Double(at.x), accuracy: 1e-4)
        XCTAssertEqual(GestureKnee.apply(CGPoint(x: 10, y: -7), deadzone: dz), CGPoint(x: 10, y: -7))
        XCTAssertEqual(GestureKnee.apply(.zero, deadzone: dz), .zero)
    }

    func testKneeNeverLagsTheFingerByMoreThanAQuarterOfTheDeadzone() {
        let dz = 4.0
        var v = 0.0
        while v <= 6 {
            let e = Double(GestureKnee.apply(CGPoint(x: v, y: 0), deadzone: dz).x)
            XCTAssertLessThanOrEqual(v - e, dz / 4 + 1e-9, "at \(v)")
            XCTAssertGreaterThanOrEqual(e, 0)
            v += 0.05
        }
    }

    func testKneeIsMonotonicSoContentNeverMovesBackwardsWhileTheFingerMovesForward() {
        var last = -1.0
        var v = 0.0
        while v <= 8 {
            let e = GestureKnee.applyScalar(v, deadzone: 4)
            XCTAssertGreaterThanOrEqual(e, last); last = e
            v += 0.01
        }
    }

    func testSensitivityScalesTravelPerDoublingAndRoundTripsOnTheSlider() {
        XCTAssertEqual(OneFingerMath.pxPerDoubling(density: 1, sensitivity: 1), 160, accuracy: 1e-9)
        XCTAssertEqual(OneFingerMath.pxPerDoubling(density: 1, sensitivity: 2), 80, accuracy: 1e-9)
        XCTAssertEqual(OneFingerMath.pxPerDoubling(density: 3, sensitivity: 0.5), 960, accuracy: 1e-9)
        XCTAssertEqual(OneFingerMath.pxPerDoubling(density: 1, sensitivity: 99), 160 / OneFingerMath.sensitivityMax, accuracy: 1e-9, "clamped")
        for s in [0.25, 0.4, 1.0, 2.0, 3.0] {
            XCTAssertEqual(OneFingerMath.sensitivityFromSlider(OneFingerMath.sliderFromSensitivity(s)), s, accuracy: 1e-9)
        }
        XCTAssertEqual(OneFingerMath.sliderFromSensitivity(OneFingerMath.sensitivityMin), 0, accuracy: 1e-9)
        XCTAssertEqual(OneFingerMath.sliderFromSensitivity(OneFingerMath.sensitivityMax), 1, accuracy: 1e-9)
    }

    func testSettingsPersistWithDefaults() {
        let suite = UserDefaults(suiteName: "tpc-test-\(UUID().uuidString)")!
        let s = GestureSettings(defaults: suite)
        XCTAssertEqual(s.mode, .pan); XCTAssertTrue(s.pinchEnabled); XCTAssertFalse(s.introSeen); XCTAssertEqual(s.zoomSensitivity, 1)
        s.mode = .zoom; s.pinchEnabled = false; s.introSeen = true; s.zoomSensitivity = 50; s.showFrameTiming = true
        let t = GestureSettings(defaults: suite)
        XCTAssertEqual(t.mode, .zoom); XCTAssertFalse(t.pinchEnabled); XCTAssertTrue(t.introSeen)
        XCTAssertEqual(t.zoomSensitivity, OneFingerMath.sensitivityMax, "clamped"); XCTAssertTrue(t.showFrameTiming)
    }

    func testFrameStatsReportSteadySixtyFpsAndCountJank() {
        let s = FrameStats()
        for i in 0...120 { s.record(Int64(i) * 16_666_667) }
        XCTAssertEqual(s.fps, 60, accuracy: 1)
        XCTAssertEqual(s.worstMs, 16.67, accuracy: 0.1)
        XCTAssertEqual(s.jankyFrames, 0)
        s.record(Int64(120) * 16_666_667 + 50_000_000)
        XCTAssertGreaterThanOrEqual(s.jankyFrames, 1)
        XCTAssertEqual(s.worstMs, 50, accuracy: 0.1)
        XCTAssertTrue(s.summary().contains("fps"))
        s.reset()
        XCTAssertEqual(s.frames, 0)
    }
}

/// Drives the gesture engine with synthetic touch sequences, exactly as the canvas view feeds it real touches.
final class GestureEngineTests: XCTestCase {
    private final class Rec {
        var begins = 0
        var pans: [CGPoint] = []
        var zooms: [(factor: Double, at: CGPoint?)] = []
        var outcomes: [GestureOutcome] = []
        var panSum: CGPoint { CGPoint(x: pans.map { $0.x }.reduce(0, +), y: pans.map { $0.y }.reduce(0, +)) }
        var zoomProduct: Double { zooms.map { $0.factor }.reduce(1, *) }
    }

    private func make(_ mode: TouchMode, pinch: Bool = true) -> (OneFingerGestureEngine, Rec, GestureTuning) {
        let e = OneFingerGestureEngine()
        let r = Rec()
        e.onBegin = { r.begins += 1 }
        e.onPan = { r.pans.append($0) }
        e.onZoom = { r.zooms.append(($0, $1)) }
        e.onFinish = { r.outcomes.append($0) }
        return (e, r, GestureTuning(mode: mode, pinchEnabled: pinch, pxPerDoubling: 160))
    }

    func testPanFollowsTheFingerExactlyFromTheFirstPixel() {
        let (e, r, t) = make(.pan)
        e.begin(id: 1, position: CGPoint(x: 100, y: 100), time: 0, tuning: t)
        for k in 1...50 { e.moved([1: CGPoint(x: 100 + Double(k), y: 100 - Double(k) / 2)], time: Double(k) * 0.01) }
        XCTAssertEqual(r.begins, 1, "begin is signalled once")
        XCTAssertGreaterThan(r.pans.count, 0)
        XCTAssertEqual(Double(r.panSum.x), 50, accuracy: 1e-9, "content moved exactly as far as the finger")
        XCTAssertEqual(Double(r.panSum.y), -25, accuracy: 1e-9)
        XCTAssertTrue(r.pans.allSatisfy { $0.x >= 0 }, "never moves backwards while the finger moves forward")
        e.fingerUp(id: 1, time: 0.6)
        XCTAssertEqual(r.outcomes, [.moved])
    }

    func testMovementStartsImmediatelyWithoutALargeJump() {
        let (e, r, t) = make(.pan)
        e.begin(id: 1, position: .zero, time: 0, tuning: t)
        for k in 1...10 { e.moved([1: CGPoint(x: Double(k), y: 0)], time: Double(k) * 0.01) }
        XCTAssertEqual(r.pans.count, 10, "every event moves the content, from the very first pixel")
        XCTAssertLessThan(Double(r.pans[0].x), 1, "the first pixel moves the content by less than the finger moved")
        XCTAssertGreaterThan(Double(r.pans[0].x), 0)
        XCTAssertLessThanOrEqual(r.pans.map { Double($0.x) }.max()!, 2.0001, "the soft start never exceeds twice the finger step: no jump")
        XCTAssertEqual(Double(r.panSum.x), 10, accuracy: 1e-9, "nothing is lost")
    }

    func testTinyMovementThenLiftIsATapAndCommitsNothing() {
        let (e, r, t) = make(.pan)
        e.begin(id: 1, position: CGPoint(x: 50, y: 50), time: 0, tuning: t)
        e.moved([1: CGPoint(x: 52, y: 51)], time: 0.05)
        e.moved([1: CGPoint(x: 53, y: 52)], time: 0.08)
        e.fingerUp(id: 1, time: 0.1)
        XCTAssertEqual(r.outcomes, [.tap])
    }

    func testRestingFingerIsALongPressAndLaterEventsAreIgnored() {
        let (e, r, t) = make(.pan)
        e.begin(id: 1, position: CGPoint(x: 50, y: 50), time: 0, tuning: t)
        XCTAssertEqual(e.longPressDeadline ?? -1, t.longPress, accuracy: 1e-9)
        e.moved([1: CGPoint(x: 50.5, y: 50)], time: 0.1) // tremor
        e.longPressTimerFired()
        XCTAssertEqual(r.outcomes, [.longPress])
        e.moved([1: CGPoint(x: 90, y: 90)], time: 0.6)
        e.fingerUp(id: 1, time: 0.7)
        XCTAssertEqual(r.outcomes, [.longPress], "the app owns the touch after a long press")
    }

    func testASlowCarefulDragIsNotALongPress() {
        let (e, r, t) = make(.pan)
        e.begin(id: 1, position: CGPoint(x: 100, y: 100), time: 0, tuning: t)
        for k in 1...4 { e.moved([1: CGPoint(x: 100 + 1.2 * Double(k), y: 100)], time: 0.1 * Double(k)) }
        e.longPressTimerFired()
        XCTAssertEqual(r.outcomes, [], "still moving, so it stays a drag")
        for k in 5...20 { e.moved([1: CGPoint(x: 100 + 1.2 * Double(k), y: 100)], time: 0.1 * Double(k)) }
        e.fingerUp(id: 1, time: 2.1)
        XCTAssertEqual(r.outcomes, [.moved])
        XCTAssertEqual(Double(r.panSum.x), 24, accuracy: 1e-9)
    }

    func testOneFingerZoomUpDoublesAndReturningRestoresExactly() {
        let (e, r, t) = make(.zoom)
        e.begin(id: 1, position: CGPoint(x: 100, y: 400), time: 0, tuning: t)
        for k in 1...160 { e.moved([1: CGPoint(x: 100, y: 400 - Double(k))], time: Double(k) * 0.005) }
        XCTAssertEqual(r.zoomProduct, 2, accuracy: 1e-9, "160 points up is one doubling")
        XCTAssertTrue(r.zooms.allSatisfy { $0.at == nil }, "one finger zooms about the cell centre")
        for k in stride(from: 159, through: 0, by: -1) { e.moved([1: CGPoint(x: 100, y: 400 - Double(k))], time: 1 + Double(160 - k) * 0.005) }
        XCTAssertEqual(r.zoomProduct, 1, accuracy: 1e-9, "up then the same distance down returns to the start")
        XCTAssertTrue(r.pans.isEmpty, "zoom mode never pans")
        e.fingerUp(id: 1, time: 3)
        XCTAssertEqual(r.outcomes, [.moved])
    }

    func testSlidingDownZoomsOutAndHorizontalMovementIsIgnoredInZoomMode() {
        let (e, r, t) = make(.zoom)
        e.begin(id: 1, position: CGPoint(x: 100, y: 100), time: 0, tuning: t)
        for k in 1...40 { e.moved([1: CGPoint(x: 100 + Double(k) * 2, y: 100)], time: Double(k) * 0.01) }
        XCTAssertTrue(r.zooms.isEmpty); XCTAssertEqual(r.begins, 0)
        for k in 1...80 { e.moved([1: CGPoint(x: 180, y: 100 + Double(k))], time: 0.5 + Double(k) * 0.01) }
        XCTAssertEqual(r.zoomProduct, pow(2.0, -0.5), accuracy: 1e-9, "80 points down is half a halving (160 points per doubling)")
        e.fingerUp(id: 1, time: 2)
    }

    func testPinchZoomsAboutTheCentroidWhenEnabled() {
        let (e, r, t) = make(.pan, pinch: true)
        e.begin(id: 1, position: CGPoint(x: 100, y: 100), time: 0, tuning: t)
        e.fingerDown(id: 2, position: CGPoint(x: 200, y: 100), time: 0.02)
        e.moved([1: CGPoint(x: 90, y: 100), 2: CGPoint(x: 210, y: 100)], time: 0.04)
        XCTAssertEqual(r.zooms.count, 1)
        XCTAssertEqual(r.zooms[0].factor, 1.2, accuracy: 1e-9)
        XCTAssertEqual(Double(r.zooms[0].at!.x), 150, accuracy: 1e-9)
        XCTAssertTrue(r.pans.isEmpty, "a symmetric pinch does not pan")
        e.moved([1: CGPoint(x: 100, y: 110), 2: CGPoint(x: 220, y: 110)], time: 0.06)
        XCTAssertGreaterThan(r.pans.count, 0, "two fingers also pan with their centre")
        e.fingerUp(id: 2, time: 0.1); e.fingerUp(id: 1, time: 0.12)
        XCTAssertEqual(r.outcomes, [.moved])
    }

    func testPinchIsIgnoredWhenSwitchedOff() {
        let (e, r, t) = make(.pan, pinch: false)
        e.begin(id: 1, position: CGPoint(x: 100, y: 100), time: 0, tuning: t)
        e.fingerDown(id: 2, position: CGPoint(x: 200, y: 100), time: 0.02)
        e.moved([1: CGPoint(x: 60, y: 100), 2: CGPoint(x: 240, y: 100)], time: 0.04)
        XCTAssertTrue(r.zooms.isEmpty); XCTAssertTrue(r.pans.isEmpty)
        e.fingerUp(id: 2, time: 0.1); e.fingerUp(id: 1, time: 0.12)
    }

    func testLiftingOneFingerAfterAPinchContinuesWithoutAJump() {
        let (e, r, t) = make(.pan)
        e.begin(id: 1, position: CGPoint(x: 100, y: 100), time: 0, tuning: t)
        e.fingerDown(id: 2, position: CGPoint(x: 200, y: 100), time: 0.02)
        e.moved([1: CGPoint(x: 90, y: 100), 2: CGPoint(x: 210, y: 100)], time: 0.04)
        e.fingerUp(id: 2, time: 0.06)
        let before = r.pans.count
        e.moved([1: CGPoint(x: 95, y: 100)], time: 0.08)
        XCTAssertEqual(r.pans.count, before, "the first event after a lift only re-anchors")
        e.moved([1: CGPoint(x: 105, y: 100)], time: 0.1)
        XCTAssertEqual(Double(r.pans.last!.x), 10, accuracy: 1e-9)
        e.fingerUp(id: 1, time: 0.12)
        XCTAssertEqual(r.outcomes, [.moved])
    }

    func testCancelFinishesAsTapIfNothingMovedElseMoved() {
        let (e, r, t) = make(.pan)
        e.begin(id: 1, position: .zero, time: 0, tuning: t)
        e.cancel()
        XCTAssertEqual(r.outcomes, [.tap])
        let (e2, r2, t2) = make(.pan)
        e2.begin(id: 1, position: .zero, time: 0, tuning: t2)
        e2.moved([1: CGPoint(x: 30, y: 0)], time: 0.05)
        e2.cancel()
        XCTAssertEqual(r2.outcomes, [.moved])
    }
}
