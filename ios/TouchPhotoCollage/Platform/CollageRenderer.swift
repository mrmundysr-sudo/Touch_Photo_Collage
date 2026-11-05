import UIKit
import CoreGraphics

/// Renders a project at any resolution. The same code path serves the live preview, the live drag layer and the final
/// export, so what you see is what you save. Originals are only ever read.
///
/// All drawing happens in a y-down context whose units are whatever `width`/`height` say (pixels for bitmaps, points
/// for the on-screen live layer); every size in the project is relative to the shorter canvas side.
final class CollageRenderer: @unchecked Sendable {
    struct Options {
        /// Keep alpha for a transparent background (PNG). When false, transparent backgrounds render white.
        var keepTransparent = false
        /// Draw placeholders for empty cells (editor only).
        var showPlaceholders = false
    }

    private let provider: ImageProvider

    init(provider: ImageProvider) { self.provider = provider }

    func render(_ project: CollageProject, width: Int, height: Int, options: Options = Options()) -> CGImage? {
        guard let ctx = CG.makeContext(width: width, height: height, alpha: options.keepTransparent) else { return nil }
        let w = Double(width), h = Double(height)
        BackgroundPainter.draw(ctx, width: w, height: h, project.background, keepTransparent: options.keepTransparent)
        let unit = LayoutEngine.unit(w, h)
        let rects = CollageRenderer.cellRects(project, width: w, height: h)
        for (i, cell) in project.cells.enumerated() where i < rects.count {
            drawCell(ctx, cell, rects[i], project, unit, options)
        }
        UIGraphicsPushContext(ctx)
        for t in project.texts { drawText(ctx, t, w, h) }
        UIGraphicsPopContext()
        return ctx.makeImage()
    }

    // MARK: cells

    private func drawCell(_ ctx: CGContext, _ cell: CellEdit, _ rect: FRect, _ project: CollageProject, _ unit: Double, _ options: Options) {
        guard let ref = cell.photo else {
            if options.showPlaceholders { drawPlaceholder(ctx, rect, project, unit) }
            return
        }
        let disp = Orientation.displaySize(ref.width, ref.height, exif: ref.exif, quarterTurns: cell.rotation)
        let region = CropMath.region(imgAspect: disp.aspect, cellAspect: rect.w / rect.h, zoom: cell.zoom, cx: cell.cx, cy: cell.cy, fit: cell.fit)
        let part = CropMath.photoPart(region)
        let dest = CropMath.destRect(region, cell: rect)
        let radius = min(project.style.cornerRadius * unit, min(dest.w, dest.h) / 2)
        let pxPerSrc = dest.w / (part.w * Double(disp.w))
        guard let img = provider.image(for: ref, sample: CropMath.sampleFor(pxPerSrc)) else {
            drawBroken(ctx, dest, radius)
            return
        }
        paintCell(ctx, img, cell, rect, project, unit, allowSharpen: true)
    }

    /// Paints one photo cell from an already decoded image (any sample size). Used by `drawCell` and by live gesture
    /// drawing, so what you see while dragging is exactly what is rendered afterwards.
    private func paintCell(_ ctx: CGContext, _ image: CGImage, _ cell: CellEdit, _ rect: FRect, _ project: CollageProject, _ unit: Double, allowSharpen: Bool) {
        guard let ref = cell.photo else { return }
        let disp = Orientation.displaySize(ref.width, ref.height, exif: ref.exif, quarterTurns: cell.rotation)
        let region = CropMath.region(imgAspect: disp.aspect, cellAspect: rect.w / rect.h, zoom: cell.zoom, cx: cell.cx, cy: cell.cy, fit: cell.fit)
        let part = CropMath.photoPart(region)
        let dest = CropMath.destRect(region, cell: rect)
        let radius = min(project.style.cornerRadius * unit, min(dest.w, dest.h) / 2)

        let aff = Orientation.totalAffine(rawW: image.width, rawH: image.height, exif: ref.exif, quarterTurns: cell.rotation, mirror: cell.mirror)
        let dw = Orientation.displaySize(image.width, image.height, exif: ref.exif, quarterTurns: cell.rotation)
        let sx = dest.w / (part.w * Double(dw.w))
        let sy = dest.h / (part.h * Double(dw.h))
        let tx = dest.l - part.l * dest.w / part.w
        let ty = dest.t - part.t * dest.h / part.h
        let full = aff.then(Affine(a: sx, d: sy, tx: tx, ty: ty))

        let cm = ColorMath.forCell(cell.adjustments, cell.filter)
        let source = ColorMath.isIdentity(cm) ? image : ColorFilterCache.shared.apply(cm, to: image)
        let rf = CG.rect(dest)

        if allowSharpen && cell.adjustments.sharpness > 0.001, drawSharpened(ctx, source, full, rf, radius, cell.adjustments.sharpness) {
            // done
        } else {
            ctx.saveGState()
            ctx.addPath(CG.roundedPath(rf, radius: radius))
            ctx.clip()
            drawPhoto(ctx, source, full)
            ctx.restoreGState()
        }
        if project.style.borderWidth > 0 {
            let bw = project.style.borderWidth * unit
            let inset = bw / 2
            ctx.saveGState()
            ctx.setStrokeColor(CG.color(project.style.borderColor))
            ctx.setLineWidth(CGFloat(bw))
            ctx.addPath(CG.roundedPath(rf.insetBy(dx: inset, dy: inset), radius: max(0, radius - inset)))
            ctx.strokePath()
            ctx.restoreGState()
        }
        if !cell.caption.isBlank { drawCaption(ctx, cell.caption.display(), rf, radius) }
    }

    /// Draws raw (un-oriented) pixels through the combined raw -> canvas affine.
    private func drawPhoto(_ ctx: CGContext, _ img: CGImage, _ full: Affine) {
        ctx.saveGState()
        ctx.concatenate(full.cg)
        ctx.translateBy(x: 0, y: CGFloat(img.height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        ctx.restoreGState()
    }

    /// Repaints a single cell (background, photo, border, caption and text overlays) onto `ctx`, a y-down context, using
    /// the live crop in `cell`. Nothing is decoded and the project is not touched, which makes it cheap enough to run
    /// every display frame while a finger is dragging. Sharpening is skipped while live (the final render applies it).
    func drawCellLive(_ ctx: CGContext, project: CollageProject, index: Int, cell: CellEdit, image: CGImage, width: Double, height: Double) {
        let rects = CollageRenderer.cellRects(project, width: width, height: height)
        guard index < rects.count else { return }
        let rect = rects[index]
        let unit = LayoutEngine.unit(width, height)
        ctx.saveGState()
        ctx.clip(to: CG.rect(rect))
        if project.background.type == .transparent {
            LiveBackdrop.drawChecker(ctx, in: CG.rect(rect))
        } else {
            BackgroundPainter.draw(ctx, width: width, height: height, project.background, keepTransparent: true)
        }
        paintCell(ctx, image, cell, rect, project, unit, allowSharpen: false)
        UIGraphicsPushContext(ctx)
        for t in project.texts { drawText(ctx, t, width, height) }
        UIGraphicsPopContext()
        ctx.restoreGState()
    }

    /// Colour-correct into a cell-sized temp bitmap, sharpen, then draw with the rounded mask.
    private func drawSharpened(_ ctx: CGContext, _ src: CGImage, _ full: Affine, _ rf: CGRect, _ radius: Double, _ amount: Double) -> Bool {
        let w = max(Int(rf.width), 1), h = max(Int(rf.height), 1)
        if w * h > 40_000_000 { return false }
        guard let tmp = CG.makeContext(width: w, height: h, alpha: true) else { return false }
        tmp.translateBy(x: -rf.minX, y: -rf.minY)
        drawPhoto(tmp, src, full)
        guard let data = tmp.data else { return false }
        let count = w * h * 4
        let buf = UnsafeMutableBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: count)
        let sharp = Sharpen.apply(Array(buf), w: w, h: h, amount: amount)
        for i in 0..<count { buf[i] = sharp[i] }
        guard let out = tmp.makeImage() else { return false }
        ctx.saveGState()
        ctx.addPath(CG.roundedPath(rf, radius: radius))
        ctx.clip()
        CG.draw(ctx, out, in: CGRect(x: rf.minX, y: rf.minY, width: CGFloat(w), height: CGFloat(h)))
        ctx.restoreGState()
        return true
    }

    private func drawCaption(_ ctx: CGContext, _ text: String, _ rf: CGRect, _ radius: Double) {
        let base = min(rf.width, rf.height)
        let size = max(base * 0.062, 10)
        let shadow = NSShadow()
        shadow.shadowBlurRadius = size * 0.15
        shadow.shadowOffset = CGSize(width: 0, height: size * 0.05)
        shadow.shadowColor = UIColor(white: 0, alpha: 0x99 / 255.0)
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byTruncatingTail
        let font = UIFont.systemFont(ofSize: size, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white, .paragraphStyle: para, .shadow: shadow]
        let pad = size * 0.8
        let avail = max(10, rf.width - 2 * pad)
        let str = NSAttributedString(string: text, attributes: attrs)
        let natural = str.boundingRect(with: CGSize(width: avail, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], context: nil).height
        let textH = ceil(min(natural, font.lineHeight * 2))
        let scrimH = textH + pad * 2
        ctx.saveGState()
        ctx.addPath(CG.roundedPath(rf, radius: radius))
        ctx.clip()
        let colors = [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0xB0 / 255.0)] as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(), colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: rf.maxY - scrimH), end: CGPoint(x: 0, y: rf.maxY), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        UIGraphicsPushContext(ctx)
        str.draw(with: CGRect(x: rf.minX + pad, y: rf.maxY - pad - textH, width: avail, height: textH), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        UIGraphicsPopContext()
        ctx.restoreGState()
    }

    private func drawPlaceholder(_ ctx: CGContext, _ rect: FRect, _ project: CollageProject, _ unit: Double) {
        let r = min(project.style.cornerRadius * unit, min(rect.w, rect.h) / 2)
        ctx.saveGState()
        ctx.setFillColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 0x33 / 255.0))
        ctx.addPath(CG.roundedPath(CG.rect(rect), radius: r))
        ctx.fillPath()
        ctx.setStrokeColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 0x99 / 255.0))
        ctx.setLineWidth(CGFloat(max(2, min(rect.w, rect.h) * 0.02)))
        ctx.setLineCap(.round)
        let s = min(rect.w, rect.h) * 0.12
        ctx.move(to: CGPoint(x: rect.cx - s, y: rect.cy)); ctx.addLine(to: CGPoint(x: rect.cx + s, y: rect.cy))
        ctx.move(to: CGPoint(x: rect.cx, y: rect.cy - s)); ctx.addLine(to: CGPoint(x: rect.cx, y: rect.cy + s))
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func drawBroken(_ ctx: CGContext, _ dest: FRect, _ radius: Double) {
        ctx.saveGState()
        ctx.setFillColor(CG.color(0xFF7A7A7A))
        ctx.addPath(CG.roundedPath(CG.rect(dest), radius: radius))
        ctx.fillPath()
        ctx.restoreGState()
    }

    // MARK: text

    /// Draws one overlay. Must be called between `UIGraphicsPushContext` / `Pop` of a y-down context.
    private func drawText(_ ctx: CGContext, _ t: TextOverlay, _ w: Double, _ h: Double) {
        if t.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        let l = TextStyling.layout(t, canvasW: w, canvasH: h)
        ctx.saveGState()
        ctx.translateBy(x: CGFloat(t.x * w), y: CGFloat(t.y * h))
        ctx.rotate(by: CGFloat(t.rotation * .pi / 180))
        if t.backgroundColor != 0 {
            let pad = l.fontSize * 0.4
            let box = CGRect(x: -l.width / 2 - pad, y: -l.height / 2 - pad * 0.6, width: l.width + pad * 2, height: l.height + pad * 1.2)
            ctx.setFillColor(CG.color(t.backgroundColor))
            ctx.addPath(CG.roundedPath(box, radius: pad))
            ctx.fillPath()
        }
        l.text.draw(with: CGRect(x: -l.width / 2, y: -l.height / 2, width: l.width, height: l.height), options: [.usesLineFragmentOrigin], context: nil)
        ctx.restoreGState()
    }

    /// Axis-aligned hit boxes (canvas units) for text overlays; used by the editor to drag text.
    func textBounds(_ project: CollageProject, width: Double, height: Double) -> [CGRect] {
        project.texts.map { t in
            if t.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .zero }
            let l = TextStyling.layout(t, canvasW: width, canvasH: height)
            let pad = l.fontSize * 0.4
            return CGRect(x: t.x * width - l.width / 2 - pad, y: t.y * height - l.height / 2 - pad, width: l.width + pad * 2, height: l.height + pad * 2)
        }
    }

    static func cellRects(_ project: CollageProject, width: Double, height: Double) -> [FRect] {
        let unit = LayoutEngine.unit(width, height)
        return LayoutEngine.cellRects(project.layout, canvasW: width, canvasH: height, margin: project.style.margin * unit, spacing: project.style.spacing * unit)
    }
}

/// Checkerboard shown behind transparent backgrounds.
enum LiveBackdrop {
    static func drawChecker(_ ctx: CGContext, in rect: CGRect, square s: CGFloat = 12) {
        ctx.saveGState()
        ctx.clip(to: rect)
        let a = CGColor(gray: 0.9, alpha: 1), b = CGColor(gray: 1, alpha: 1)
        var y = rect.minY, r = 0
        while y < rect.maxY {
            var x = rect.minX, c = 0
            while x < rect.maxX {
                ctx.setFillColor((r + c) % 2 == 0 ? a : b)
                ctx.fill(CGRect(x: x, y: y, width: s, height: s))
                x += s; c += 1
            }
            y += s; r += 1
        }
        ctx.restoreGState()
    }
}
