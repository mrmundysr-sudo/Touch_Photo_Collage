import UIKit
import CoreGraphics

/// Colour and drawing helpers. All drawing in this app happens in a *y-down* context (origin top-left), the same
/// convention as the Android canvas, so the engine's coordinates map directly.
enum CG {
    static func color(_ c: ARGB, alpha: Double? = nil) -> CGColor {
        let a = alpha ?? Double((c >> 24) & 0xFF) / 255
        return CGColor(
            srgbRed: CGFloat((c >> 16) & 0xFF) / 255, green: CGFloat((c >> 8) & 0xFF) / 255, blue: CGFloat(c & 0xFF) / 255, alpha: CGFloat(a)
        )
    }

    static func uiColor(_ c: ARGB) -> UIColor { UIColor(cgColor: color(c)) }

    static func rect(_ r: FRect) -> CGRect { CGRect(x: r.l, y: r.t, width: r.w, height: r.h) }

    /// Creates a bitmap context and flips it to y-down.
    static func makeContext(width: Int, height: Int, alpha: Bool) -> CGContext? {
        let info = alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
        guard width > 0, height > 0, let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: ImageIOUtil.srgb, bitmapInfo: info
        ) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        return ctx
    }

    /// Draws `image` upright into `rect` of a y-down context.
    static func draw(_ ctx: CGContext, _ image: CGImage, in rect: CGRect) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        ctx.restoreGState()
    }

    static func roundedPath(_ r: CGRect, radius: CGFloat) -> CGPath {
        let rad = max(0, min(radius, min(r.width, r.height) / 2))
        return CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)
    }
}
