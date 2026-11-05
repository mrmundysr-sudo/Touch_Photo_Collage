import UIKit
import SwiftUI

/// Everything the canvas needs from the editor. Closures call straight into `AppModel`.
struct CanvasProps {
    var project: CollageProject
    var frame: PreviewFrame?
    var selection: EditSelection
    var mode: TouchMode
    var pinchEnabled: Bool
    var sensitivity: Double
    var primary: UIColor
    var live: LiveGesture
    var renderer: CollageRenderer
    var liveImage: (Int) -> CGImage?
    var onSelectCell: (Int?) -> Void
    var onSelectText: (Int?) -> Void
    var onTransform: (_ index: Int, _ dx: Double, _ dy: Double, _ zoom: Double, _ fx: Double, _ fy: Double, _ cw: Double, _ ch: Double) -> Void
    var onMoveText: (Int, Double, Double) -> Void
    var onSwap: (Int, Int) -> Void
    var onGestureEnd: () -> Void
    var onCommit: (_ index: Int, _ zoom: Double, _ cx: Double, _ cy: Double) -> Void
    var onZoomStep: (Double) -> Void
    var onPanStep: (Double, Double) -> Void
    var onReset: () -> Void
}

/// A layer that delegates its drawing, used for the checkerboard, the live cell and the selection overlay.
final class DrawLayer: CALayer {
    var drawHandler: ((CGContext, CGRect) -> Void)?

    override func draw(in ctx: CGContext) {
        // On iOS a UIView-hosted layer already hands us a top-left-origin (y-down) context, which is what the renderer and
        // every overlay expect: no flip here (flipping it again drew the selection outline upside down).
        drawHandler?(ctx, bounds)
    }
}

/// The collage canvas.
///
/// One finger drags the photo (PAN) or slides it in and out (ZOOM), two fingers pinch-zoom if enabled, a long press picks
/// the photo up so it can be dropped on another cell to swap, and dragging text moves it. Touch handling is deliberately
/// done with raw UIKit touches feeding `OneFingerGestureEngine`: no system recogniser can delay, steal or smooth the
/// first points of a drag, so the content follows the finger from the first point.
final class CanvasUIView: UIView {
    var props: CanvasProps! {
        didSet { propsChanged(old: oldValue) }
    }

    private let checkerLayer = DrawLayer()
    private let frameLayer = CALayer()
    private let liveLayer = DrawLayer()
    private let overlayLayer = DrawLayer()
    private let engine = OneFingerGestureEngine()

    private enum Interaction {
        case none
        case text(index: Int, offset: CGPoint)
        case cell(index: Int)
        case swap(from: Int)
        case ignored
    }

    private var interaction = Interaction.none
    private var touchIds: [UITouch: Int] = [:]
    private var nextId = 1
    private var primaryTouch: UITouch?
    private var rects: [FRect] = []
    private var imgAspect = 1.0
    private var cellFit = false
    private var fallback = false
    private var longPressItem: DispatchWorkItem?
    private var dragPos = CGPoint.zero
    private var commitTimeout: DispatchWorkItem?
    private var lastFrameImage: CGImage?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        clipsToBounds = true
        isAccessibilityElement = true
        accessibilityIdentifier = "collageCanvas"
        accessibilityTraits = [.adjustable, .image]
        let scale = UIScreen.main.scale
        for l in [checkerLayer, liveLayer, overlayLayer] as [DrawLayer] { l.contentsScale = scale }
        frameLayer.contentsScale = scale
        frameLayer.contentsGravity = .resize
        layer.addSublayer(checkerLayer)
        layer.addSublayer(frameLayer)
        layer.addSublayer(liveLayer)
        layer.addSublayer(overlayLayer)
        checkerLayer.drawHandler = { ctx, b in LiveBackdrop.drawChecker(ctx, in: b) }
        liveLayer.drawHandler = { [weak self] ctx, b in self?.drawLive(ctx, b) }
        overlayLayer.drawHandler = { [weak self] ctx, b in self?.drawOverlay(ctx, b) }
        wireEngine()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for l in [checkerLayer, frameLayer, liveLayer, overlayLayer] { l.frame = bounds }
        CATransaction.commit()
        for l in [checkerLayer, liveLayer, overlayLayer] { l.setNeedsDisplay() }
    }

    // MARK: props

    private func propsChanged(old: CanvasProps?) {
        guard let p = props else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let f = p.frame?.image, f !== lastFrameImage {
            lastFrameImage = f
            frameLayer.contents = f
        } else if p.frame == nil, lastFrameImage != nil {
            lastFrameImage = nil
            frameLayer.contents = nil
        }
        CATransaction.commit()

        let transparent = p.project.background.type == .transparent
        if (old?.project.background.type == .transparent) != transparent { checkerLayer.setNeedsDisplay() }
        checkerLayer.isHidden = !transparent

        if old?.selection != p.selection || old?.primary != p.primary || old?.frame?.textBounds != p.frame?.textBounds { overlayLayer.setNeedsDisplay() }

        // Remove the live layer once the committed project's frame is what is on screen.
        if p.live.commitPending, let f = p.frame {
            let i = p.live.index
            if f.forProject.cells.indices.contains(i) {
                let c = f.forProject.cells[i]
                if c.zoom == p.live.zoom && c.cx == p.live.cx && c.cy == p.live.cy { endLive() }
            }
        }

        accessibilityLabel = "Collage preview with \(p.project.photoCount) photos. Touch mode \(p.mode.label). Long press a photo and drop it onto another to swap."
        if let i = p.selection.cell, p.project.cells.indices.contains(i), p.project.cells[i].photo != nil {
            let c = p.project.cells[i]
            accessibilityValue = String(format: "Photo %d selected, zoom %.1f times, centre %.2f %.2f", i + 1, c.zoom, c.cx, c.cy)
        } else {
            accessibilityValue = "No photo selected"
        }
        let actions: [(String, () -> Void)] = [
            ("Zoom in on selected photo", { [weak self] in self?.props.onZoomStep(1.25) }),
            ("Zoom out on selected photo", { [weak self] in self?.props.onZoomStep(0.8) }),
            ("Move selected photo left", { [weak self] in self?.props.onPanStep(-0.1, 0) }),
            ("Move selected photo right", { [weak self] in self?.props.onPanStep(0.1, 0) }),
            ("Move selected photo up", { [weak self] in self?.props.onPanStep(0, -0.1) }),
            ("Move selected photo down", { [weak self] in self?.props.onPanStep(0, 0.1) }),
            ("Reset selected photo position", { [weak self] in self?.props.onReset() }),
        ]
        accessibilityCustomActions = actions.map { entry in
            UIAccessibilityCustomAction(name: entry.0) { _ in entry.1(); return true }
        }
    }

    override func accessibilityIncrement() { props.onZoomStep(1.25) }
    override func accessibilityDecrement() { props.onZoomStep(0.8) }

    private func endLive() {
        commitTimeout?.cancel()
        props.live.clear()
        liveLayer.setNeedsDisplay()
    }

    // MARK: drawing

    private func drawLive(_ ctx: CGContext, _ b: CGRect) {
        guard let p = props, p.live.active, let img = p.live.image, p.project.cells.indices.contains(p.live.index) else { return }
        var cell = p.project.cells[p.live.index]
        cell.zoom = p.live.zoom; cell.cx = p.live.cx; cell.cy = p.live.cy
        p.renderer.drawCellLive(ctx, project: p.project, index: p.live.index, cell: cell, image: img, width: Double(b.width), height: Double(b.height))
    }

    private func drawOverlay(_ ctx: CGContext, _ b: CGRect) {
        guard let p = props else { return }
        let color = p.primary.resolvedColor(with: traitCollection).cgColor
        let rs = CollageRenderer.cellRects(p.project, width: Double(b.width), height: Double(b.height))
        if let i = p.selection.cell, rs.indices.contains(i) {
            ctx.setStrokeColor(color); ctx.setLineWidth(3)
            ctx.addPath(CG.roundedPath(CG.rect(rs[i]).insetBy(dx: 1.5, dy: 1.5), radius: 6)); ctx.strokePath()
        }
        if let i = p.selection.text, let tb = p.frame?.textBounds, tb.indices.contains(i) {
            ctx.setStrokeColor(color); ctx.setLineWidth(2); ctx.setLineDash(phase: 0, lengths: [7, 5])
            ctx.addPath(CG.roundedPath(tb[i], radius: 6)); ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
        }
        if case .swap(let from) = interaction, rs.indices.contains(from) {
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.35))
            ctx.addPath(CG.roundedPath(CG.rect(rs[from]), radius: 6)); ctx.fillPath()
            if let target = rs.firstIndex(where: { $0.contains(x: Double(dragPos.x), y: Double(dragPos.y)) }), target != from {
                let r = CG.rect(rs[target])
                ctx.setFillColor(color.copy(alpha: 0.35) ?? color)
                ctx.addPath(CG.roundedPath(r, radius: 6)); ctx.fillPath()
                ctx.setStrokeColor(color); ctx.setLineWidth(4)
                ctx.addPath(CG.roundedPath(r.insetBy(dx: 2, dy: 2), radius: 6)); ctx.strokePath()
            }
            let w: CGFloat = 84, h: CGFloat = 63
            ctx.setFillColor(color.copy(alpha: 0.85) ?? color)
            ctx.addPath(CG.roundedPath(CGRect(x: dragPos.x - w / 2, y: dragPos.y - h / 2, width: w, height: h), radius: 10)); ctx.fillPath()
        }
    }

    // MARK: engine wiring

    private func tuning() -> GestureTuning {
        GestureTuning(
            mode: props.mode, pinchEnabled: props.pinchEnabled,
            pxPerDoubling: OneFingerMath.pxPerDoubling(density: 1, sensitivity: props.sensitivity)
        )
    }

    private func wireEngine() {
        engine.onBegin = { [weak self] in
            guard let self = self, case .cell(let idx) = self.interaction, self.props.project.cells.indices.contains(idx) else { return }
            let c = self.props.project.cells[idx]
            if let img = self.props.liveImage(idx) {
                self.fallback = false
                self.props.live.begin(index: idx, zoom: c.zoom, cx: c.cx, cy: c.cy, image: img)
            } else {
                self.fallback = true
            }
        }
        engine.onPan = { [weak self] d in
            guard let self = self, case .cell(let idx) = self.interaction, self.rects.indices.contains(idx) else { return }
            let r = self.rects[idx]
            if self.fallback {
                self.props.onTransform(idx, Double(d.x), Double(d.y), 1, 0.5, 0.5, r.w, r.h)
            } else {
                self.props.live.pan(dx: Double(d.x), dy: Double(d.y), imgAspect: self.imgAspect, cellW: r.w, cellH: r.h, fit: self.cellFit)
                self.invalidateLive(r)
            }
        }
        engine.onZoom = { [weak self] factor, centroid in
            guard let self = self, case .cell(let idx) = self.interaction, self.rects.indices.contains(idx) else { return }
            let r = self.rects[idx]
            let fx = centroid.map { min(max((Double($0.x) - r.l) / r.w, 0), 1) } ?? 0.5
            let fy = centroid.map { min(max((Double($0.y) - r.t) / r.h, 0), 1) } ?? 0.5
            if self.fallback {
                self.props.onTransform(idx, 0, 0, factor, fx, fy, r.w, r.h)
            } else {
                self.props.live.zoomBy(factor, fx: fx, fy: fy, imgAspect: self.imgAspect, cellAspect: r.w / r.h, fit: self.cellFit)
                self.invalidateLive(r)
            }
        }
        engine.onFinish = { [weak self] outcome in self?.finish(outcome) }
    }

    private func invalidateLive(_ r: FRect) {
        liveLayer.setNeedsDisplay(CG.rect(r).insetBy(dx: -2, dy: -2))
    }

    private func finish(_ outcome: GestureOutcome) {
        longPressItem?.cancel()
        guard case .cell(let idx) = interaction else { return }
        switch outcome {
        case .moved:
            if fallback {
                props.onGestureEnd()
            } else if props.live.active {
                props.onCommit(idx, props.live.zoom, props.live.cx, props.live.cy)
                props.live.markCommitted()
                let item = DispatchWorkItem { [weak self] in self?.endLive() }
                commitTimeout = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: item)
            }
            interaction = .none
        case .tap:
            props.live.clear(); liveLayer.setNeedsDisplay()
            if fallback { props.onGestureEnd() }
            interaction = .none
        case .longPress:
            props.live.clear(); liveLayer.setNeedsDisplay()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            dragPos = primaryTouch.map { $0.location(in: self) } ?? .zero
            interaction = .swap(from: idx)
            overlayLayer.setNeedsDisplay()
        }
    }

    // MARK: touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches.sorted(by: { $0.timestamp < $1.timestamp }) {
            let id = nextId; nextId += 1
            touchIds[t] = id
            handleDown(t, id: id)
        }
    }

    private func handleDown(_ t: UITouch, id: Int) {
        let pos = t.location(in: self)
        switch interaction {
        case .none:
            primaryTouch = t
            if let ti = props.frame?.textBounds.lastIndex(where: { !$0.isEmpty && $0.contains(pos) }) {
                props.onSelectText(ti)
                let tx = props.project.texts[ti]
                let center = CGPoint(x: tx.x * Double(bounds.width), y: tx.y * Double(bounds.height))
                interaction = .text(index: ti, offset: CGPoint(x: center.x - pos.x, y: center.y - pos.y))
                return
            }
            rects = CollageRenderer.cellRects(props.project, width: Double(bounds.width), height: Double(bounds.height))
            guard let idx = rects.firstIndex(where: { $0.contains(x: Double(pos.x), y: Double(pos.y)) }) else {
                props.onSelectCell(nil)
                interaction = .ignored
                return
            }
            props.onSelectCell(idx)
            let cell = props.project.cells[idx]
            guard let photo = cell.photo else { interaction = .ignored; return }
            imgAspect = Orientation.displaySize(photo.width, photo.height, exif: photo.exif, quarterTurns: cell.rotation).aspect
            cellFit = cell.fit
            fallback = false
            interaction = .cell(index: idx)
            let tn = tuning()
            engine.begin(id: id, position: pos, time: t.timestamp, tuning: tn)
            let item = DispatchWorkItem { [weak self] in self?.engine.longPressTimerFired() }
            longPressItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + tn.longPress, execute: item)
        case .cell:
            engine.fingerDown(id: id, position: pos, time: t.timestamp)
        default:
            break
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        switch interaction {
        case .text(let index, let offset):
            guard let t = primaryTouch, touches.contains(t), bounds.width > 0 else { return }
            let pos = t.location(in: self)
            props.onMoveText(index, Double(pos.x + offset.x) / Double(bounds.width), Double(pos.y + offset.y) / Double(bounds.height))
        case .cell:
            var positions: [Int: CGPoint] = [:]
            for (t, id) in touchIds { positions[id] = t.location(in: self) }
            engine.moved(positions, time: touches.map { $0.timestamp }.max() ?? 0)
        case .swap:
            guard let t = primaryTouch, touches.contains(t) else { return }
            dragPos = t.location(in: self)
            overlayLayer.setNeedsDisplay()
        default:
            break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches, cancelled: false) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches, cancelled: true) }

    private func end(_ touches: Set<UITouch>, cancelled: Bool) {
        for t in touches {
            guard let id = touchIds[t] else { continue }
            touchIds[t] = nil
            switch interaction {
            case .cell:
                if cancelled { engine.cancel() } else { engine.fingerUp(id: id, time: t.timestamp) }
            case .text:
                if t === primaryTouch { props.onGestureEnd(); interaction = .none }
            case .swap(let from):
                if t === primaryTouch {
                    let pos = t.location(in: self)
                    interaction = .none
                    let rs = CollageRenderer.cellRects(props.project, width: Double(bounds.width), height: Double(bounds.height))
                    if !cancelled, let to = rs.firstIndex(where: { $0.contains(x: Double(pos.x), y: Double(pos.y)) }), to != from { props.onSwap(from, to) }
                    overlayLayer.setNeedsDisplay()
                }
            default:
                break
            }
        }
        if touchIds.isEmpty {
            primaryTouch = nil
            if case .ignored = interaction { interaction = .none }
            if case .cell = interaction { interaction = .none }
            if case .text = interaction { interaction = .none }
            if case .swap = interaction { interaction = .none; overlayLayer.setNeedsDisplay() }
        }
    }
}

struct CollageCanvasView: UIViewRepresentable {
    var props: CanvasProps

    func makeUIView(context: Context) -> CanvasUIView {
        let v = CanvasUIView(frame: .zero)
        v.props = props
        return v
    }

    func updateUIView(_ v: CanvasUIView, context: Context) { v.props = props }
}
