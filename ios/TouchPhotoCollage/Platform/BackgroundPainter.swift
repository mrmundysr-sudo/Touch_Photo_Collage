import UIKit
import CoreGraphics

/// Draws canvas backgrounds. Textures are generated procedurally (no asset files) and scale with the canvas.
enum BackgroundPainter {
    static func draw(_ ctx: CGContext, width w: Double, height h: Double, _ bg: CanvasBackground, keepTransparent: Bool) {
        let full = CGRect(x: 0, y: 0, width: w, height: h)
        switch bg.type {
        case .transparent:
            if !keepTransparent { ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)); ctx.fill(full) }
        case .solid:
            ctx.setFillColor(CG.color(bg.color1)); ctx.fill(full)
        case .gradient:
            let a = bg.angle * .pi / 180
            let cx = w / 2, cy = h / 2
            let len = (w + h) / 2
            let colors = [CG.color(bg.color1), CG.color(bg.color2)] as CFArray
            if let g = CGGradient(colorsSpace: ImageIOUtil.srgb, colors: colors, locations: [0, 1]) {
                ctx.drawLinearGradient(
                    g,
                    start: CGPoint(x: cx - cos(a) * len / 2, y: cy - sin(a) * len / 2),
                    end: CGPoint(x: cx + cos(a) * len / 2, y: cy + sin(a) * len / 2),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            }
        case .texture:
            ctx.setFillColor(CG.color(bg.color1)); ctx.fill(full)
            texture(ctx, w, h, bg)
        }
    }

    private static func texture(_ ctx: CGContext, _ w: Double, _ h: Double, _ bg: CanvasBackground) {
        let side = min(w, h)
        let ink = bg.color2
        ctx.saveGState()
        defer { ctx.restoreGState() }
        switch bg.texture {
        case .paper, .grain:
            let paper = bg.texture == .paper
            let scale = max(paper ? side / 300 : side / 600, 0.5)
            let tw = Int((w / scale).rounded(.up)) + 1
            let th = Int((h / scale).rounded(.up)) + 1
            if let img = noiseImage(ink: ink, maxAlpha: paper ? 38 : 70, width: tw, height: th) {
                ctx.interpolationQuality = .low
                CG.draw(ctx, img, in: CGRect(x: 0, y: 0, width: Double(tw) * scale, height: Double(th) * scale))
            }
        case .linen:
            let step = max(2, side / 120)
            ctx.setLineWidth(CGFloat(max(1, step / 3)))
            ctx.setStrokeColor(CG.color(ink, alpha: 38.0 / 255))
            var x = 0.0
            while x < w { ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: h)); ctx.strokePath(); x += step }
            ctx.setStrokeColor(CG.color(ink, alpha: 26.0 / 255))
            var y = step / 2
            while y < h { ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: w, y: y)); ctx.strokePath(); y += step }
        case .dots:
            let step = side / 14
            ctx.setFillColor(CG.color(ink, alpha: 90.0 / 255))
            var row = 0
            var y = step / 2
            while y < h + step {
                var x = row % 2 == 0 ? step / 2 : step
                while x < w + step {
                    let r = step * 0.11
                    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                    x += step
                }
                y += step / 1.6; row += 1
            }
        case .stripes:
            let step = side / 16
            ctx.setFillColor(CG.color(ink, alpha: 60.0 / 255))
            ctx.translateBy(x: w / 2, y: h / 2)
            ctx.rotate(by: -.pi / 4)
            ctx.translateBy(x: -w / 2, y: -h / 2)
            let big = max(w, h) * 1.6
            var x = -big
            while x < big { ctx.fill(CGRect(x: x, y: -big, width: step / 2, height: big * 2)); x += step }
        case .checker:
            let step = side / 12
            ctx.setFillColor(CG.color(ink, alpha: 55.0 / 255))
            var iy = 0
            var y = 0.0
            while y < h {
                var ix = 0
                var x = 0.0
                while x < w {
                    if (ix + iy) % 2 == 0 { ctx.fill(CGRect(x: x, y: y, width: step, height: step)) }
                    x += step; ix += 1
                }
                y += step; iy += 1
            }
        }
    }

    // MARK: deterministic noise

    private static let lock = NSLock()
    private static var tiles: [String: [UInt8]] = [:]

    /// Deterministic 128px noise tile (seed 42) so exports look identical every time.
    private static func noiseTile(ink: ARGB, maxAlpha: Int) -> [UInt8] {
        lock.lock(); defer { lock.unlock() }
        let key = "\(ink)|\(maxAlpha)"
        if let t = tiles[key] { return t }
        let n = 128
        var rnd = JavaRandom(seed: 42)
        let r = Int((ink >> 16) & 0xFF), g = Int((ink >> 8) & 0xFF), b = Int(ink & 0xFF)
        var px = [UInt8](repeating: 0, count: n * n * 4)
        for i in 0..<(n * n) {
            let a = rnd.nextInt(maxAlpha)
            px[i * 4] = UInt8(r * a / 255); px[i * 4 + 1] = UInt8(g * a / 255); px[i * 4 + 2] = UInt8(b * a / 255); px[i * 4 + 3] = UInt8(a)
        }
        tiles[key] = px
        return px
    }

    /// An image of `width` x `height` pixels made of the repeating noise tile.
    private static func noiseImage(ink: ARGB, maxAlpha: Int, width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0, width * height < 64_000_000 else { return nil }
        let tile = noiseTile(ink: ink, maxAlpha: maxAlpha)
        var px = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            let ty = (y % 128) * 128
            for x in 0..<width {
                let s = (ty + (x % 128)) * 4
                let d = (y * width + x) * 4
                px[d] = tile[s]; px[d + 1] = tile[s + 1]; px[d + 2] = tile[s + 2]; px[d + 3] = tile[s + 3]
            }
        }
        let data = Data(px)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: ImageIOUtil.srgb,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent
        )
    }
}
