import Foundation
import CoreGraphics
import Combine

/// Uncommitted, per-frame crop of the photo under the finger.
///
/// While a finger is down the project is NOT modified: this holder owns the crop in full floating-point precision and
/// the canvas layer draws it directly from an already decoded image. Each touch event costs one cheap redraw of the
/// cell: no project copy, no re-render, no decode, no re-layout and no save. On release the final crop is committed
/// once (one undo step). Only `active`, `index` and `zoom` are published, so SwiftUI re-evaluates just the tiny views
/// that show them (mode badge, zoom readout), never the editor.
final class LiveGesture: ObservableObject {
    @Published private(set) var active = false
    @Published private(set) var index = -1
    @Published private(set) var zoom = 1.0
    private(set) var cx = 0.5
    private(set) var cy = 0.5
    /// Committed to the project, waiting for the re-rendered frame before the live layer is removed.
    private(set) var commitPending = false
    private(set) var image: CGImage?

    func begin(index: Int, zoom: Double, cx: Double, cy: Double, image: CGImage) {
        self.index = index; self.zoom = zoom; self.cx = cx; self.cy = cy; self.image = image
        commitPending = false; active = true
    }

    /// Drag the photo by `dx`/`dy` screen points inside a cell of `cellW` x `cellH` points.
    func pan(dx: Double, dy: Double, imgAspect: Double, cellW: Double, cellH: Double, fit: Bool) {
        let (nx, ny) = CropMath.pan(imgAspect: imgAspect, cellW: cellW, cellH: cellH, zoom: zoom, cx: cx, cy: cy, fit: fit, dx: dx, dy: dy)
        cx = nx; cy = ny
    }

    /// Multiply the zoom by `factor` about the point (`fx`, `fy`) of the cell (0...1).
    func zoomBy(_ factor: Double, fx: Double, fy: Double, imgAspect: Double, cellAspect: Double, fit: Bool) {
        let (z, nx, ny) = CropMath.zoomAbout(imgAspect: imgAspect, cellAspect: cellAspect, zoom: zoom, cx: cx, cy: cy, fit: fit, newZoom: zoom * factor, fx: fx, fy: fy)
        zoom = z; cx = nx; cy = ny
    }

    func markCommitted() { commitPending = true }

    /// Drop the live layer (tap, long press, or the committed frame is on screen).
    func clear() {
        active = false; commitPending = false; image = nil
    }
}
