import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import TouchPhotoCollage

enum TestSupport {
    static func tempDir(_ name: String = "tpc-tests") -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// A JPEG that is `left` on its left half and `right` on its right half, optionally tagged with an EXIF orientation.
    @discardableResult
    static func halvesJPEG(_ url: URL, w: Int = 40, h: Int = 20, exif: Int = 1, left: UIColor = .red, right: UIColor = .blue) -> URL {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1; fmt.opaque = true; fmt.preferredRange = .standard
        let img = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: fmt).image { r in
            left.setFill(); r.cgContext.fill(CGRect(x: 0, y: 0, width: w / 2, height: h))
            right.setFill(); r.cgContext.fill(CGRect(x: w / 2, y: 0, width: w - w / 2, height: h))
        }
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, img.cgImage!, [kCGImageDestinationLossyCompressionQuality: 1.0, kCGImagePropertyOrientation: exif] as CFDictionary)
        precondition(CGImageDestinationFinalize(dest))
        return url
    }

    static func solidJPEG(_ url: URL, w: Int, h: Int, color: UIColor) -> URL {
        halvesJPEG(url, w: w, h: h, left: color, right: color)
    }

    /// RGBA bytes of an image, row 0 = top.
    static func pixels(_ image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        data.withUnsafeMutableBytes { buf in
            let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return data
    }

    static func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        let p = pixels(image)
        let i = (y * image.width + x) * 4
        return (Int(p[i]), Int(p[i + 1]), Int(p[i + 2]), Int(p[i + 3]))
    }

    static func isRed(_ p: (r: Int, g: Int, b: Int, a: Int)) -> Bool { p.r > 180 && p.b < 90 }
    static func isBlue(_ p: (r: Int, g: Int, b: Int, a: Int)) -> Bool { p.b > 180 && p.r < 90 }

    /// A store + importer rooted in a fresh temp folder.
    struct Env {
        let root: URL
        let store: ProjectStore
        let importer: ImageImporter
        let provider: FileImageProvider
        let renderer: CollageRenderer
    }

    static func env() -> Env {
        let root = tempDir("env")
        let store = ProjectStore(root: root)
        let provider = FileImageProvider(mediaDir: store.mediaDir, cacheBytes: 0)
        return Env(root: root, store: store, importer: ImageImporter(mediaDir: store.mediaDir), provider: provider, renderer: CollageRenderer(provider: provider))
    }

    static func importPhoto(_ env: Env, w: Int = 40, h: Int = 20, exif: Int = 1, left: UIColor = .red, right: UIColor = .blue) throws -> PhotoRef {
        let src = halvesJPEG(env.root.appendingPathComponent("src-\(UUID().uuidString).jpg"), w: w, h: h, exif: exif, left: left, right: right)
        return try env.importer.importFile(at: src)
    }

    /// One full-bleed cell, no spacing/margin/rounding, white background.
    static func flatProject(_ photo: PhotoRef, canvas: CanvasSpec = .square, rotation: Int = 0, mirror: Bool = false, fit: Bool = false) -> CollageProject {
        var cell = CellEdit(photo: photo)
        cell.rotation = rotation; cell.mirror = mirror; cell.fit = fit
        var p = CollageProject(
            id: "flat", name: "Flat", canvas: canvas, layout: LayoutTemplate(id: "single", name: "Single", cells: [.unit]),
            style: CollageStyle(spacing: 0, margin: 0, cornerRadius: 0), cells: [cell]
        )
        p.faceMode = .off
        return ProjectOps.autoCrop(p)
    }
}

/// Polls `condition` on the main actor until it holds or the timeout passes.
@MainActor
func waitUntil(timeout: TimeInterval = 10, _ condition: () -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 30_000_000)
    }
    return condition()
}
