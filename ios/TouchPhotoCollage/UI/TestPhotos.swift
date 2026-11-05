import UIKit
import ImageIO
import UniformTypeIdentifiers

/// Synthetic photos for automated UI tests and screenshots (only used when the app is launched with `-UITestSeed`).
/// Each photo has a distinct colour scheme, a big number, and a red marker in the *raw* top-left corner; one carries
/// EXIF orientation 6 (rotated 90°) to exercise the orientation maths end to end.
enum TestPhotos {
    private static let palettes: [(UInt32, UInt32)] = [
        (0xFF3A2A66, 0xFFD9573C), (0xFF1F7A8C, 0xFFBFDBF7), (0xFF2E8B57, 0xFFF4D35E), (0xFFB5651D, 0xFFFFE5D9), (0xFF7B6CF0, 0xFFE46A9B),
    ]
    private static let sizes: [(Int, Int, Int)] = [(1200, 900, 1), (900, 1200, 1), (1000, 1000, 1), (1200, 800, 6), (1000, 750, 1)]

    static func make(count: Int) -> [URL] {
        (0..<count).compactMap { i in make(index: i) }
    }

    static func make(index i: Int) -> URL? {
        let (w, h, exif) = sizes[i % sizes.count]
        let (c1, c2) = palettes[i % palettes.count]
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        fmt.preferredRange = .standard
        let img = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: fmt).image { r in
            let ctx = r.cgContext
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [CG.color(c1), CG.color(c2)] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: w, y: h), options: [])
            ctx.setFillColor(UIColor(white: 1, alpha: 0.35).cgColor)
            let d = CGFloat(min(w, h)) * 0.55
            ctx.fillEllipse(in: CGRect(x: (CGFloat(w) - d) / 2, y: (CGFloat(h) - d) / 2, width: d, height: d))
            let text = "\(i + 1)" as NSString
            let font = UIFont.systemFont(ofSize: d * 0.7, weight: .heavy)
            let size = text.size(withAttributes: [.font: font])
            text.draw(at: CGPoint(x: (CGFloat(w) - size.width) / 2, y: (CGFloat(h) - size.height) / 2), withAttributes: [.font: font, .foregroundColor: UIColor.white])
            ctx.setFillColor(UIColor.red.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(min(w, h)) * 0.12, height: CGFloat(min(w, h)) * 0.12))
        }
        guard let cg = img.cgImage else { return nil }
        let url = IncomingFiles.directory.appendingPathComponent("sample-\(i + 1)-\(UUID().uuidString).jpg")
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: 0.9, kCGImagePropertyOrientation: exif] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? url : nil
    }
}
