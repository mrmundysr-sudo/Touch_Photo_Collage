import Foundation
import CoreGraphics
import CoreImage

/// Source of decoded (not yet oriented) images for the renderer.
protocol ImageProvider: AnyObject {
    /// Decode `ref` reduced by the power-of-two `sample`; nil if unreadable.
    func image(for ref: PhotoRef, sample: Int) -> CGImage?
}

private final class ImageBox {
    let image: CGImage
    init(_ i: CGImage) { image = i }
}

/// Decodes from the project's media folder, optionally caching decoded images (live preview) or not (export).
final class FileImageProvider: ImageProvider, @unchecked Sendable {
    private let mediaDir: URL
    private let cache: NSCache<NSString, ImageBox>?

    init(mediaDir: URL, cacheBytes: Int = 0) {
        self.mediaDir = mediaDir
        if cacheBytes > 0 {
            let c = NSCache<NSString, ImageBox>()
            c.totalCostLimit = cacheBytes
            cache = c
        } else {
            cache = nil
        }
    }

    func image(for ref: PhotoRef, sample: Int) -> CGImage? {
        let s0 = max(1, sample)
        // any cached image that is at least as detailed as requested will do
        if let c = cache {
            var s = s0
            while s >= 1 {
                if let hit = c.object(forKey: "\(ref.id)@\(s)" as NSString) { return hit.image }
                s /= 2
            }
        }
        let url = mediaDir.appendingPathComponent(ref.file)
        guard let img = ImageIOUtil.decodeRaw(url: url, width: ref.width, height: ref.height, sample: s0) else { return nil }
        cache?.setObject(ImageBox(img), forKey: "\(ref.id)@\(s0)" as NSString, cost: img.width * img.height * 4)
        return img
    }

    func clear() { cache?.removeAllObjects() }
}

/// Applies the 4x5 colour matrices of `ColorMath` to an image with Core Image (GPU), without colour management so the
/// maths runs on the same gamma-encoded values the Android app uses.
final class ColorFilterCache {
    static let shared = ColorFilterCache()

    private final class Entry {
        let source: CGImage
        let filtered: CGImage
        init(source: CGImage, filtered: CGImage) { self.source = source; self.filtered = filtered }
    }

    private let context = CIContext(options: [
        .workingColorSpace: ImageIOUtil.srgb,
        .outputColorSpace: ImageIOUtil.srgb,
    ])
    private let cache = NSCache<NSString, Entry>()

    init() { cache.totalCostLimit = 192 * 1024 * 1024 }

    func apply(_ matrix: [Double], to image: CGImage) -> CGImage {
        if ColorMath.isIdentity(matrix) { return image }
        let key = "\(ObjectIdentifier(image).hashValue)|" + matrix.map { String(format: "%.4f", $0) }.joined(separator: ",")
        if let e = cache.object(forKey: key as NSString), e.source === image { return e.filtered }
        let input = CIImage(cgImage: image)
        guard let f = CIFilter(name: "CIColorMatrix") else { return image }
        func vec(_ row: Int) -> CIVector {
            CIVector(x: CGFloat(matrix[row * 5]), y: CGFloat(matrix[row * 5 + 1]), z: CGFloat(matrix[row * 5 + 2]), w: CGFloat(matrix[row * 5 + 3]))
        }
        f.setValue(input, forKey: kCIInputImageKey)
        f.setValue(vec(0), forKey: "inputRVector")
        f.setValue(vec(1), forKey: "inputGVector")
        f.setValue(vec(2), forKey: "inputBVector")
        f.setValue(vec(3), forKey: "inputAVector")
        f.setValue(CIVector(x: CGFloat(matrix[4] / 255), y: CGFloat(matrix[9] / 255), z: CGFloat(matrix[14] / 255), w: CGFloat(matrix[19] / 255)), forKey: "inputBiasVector")
        guard let out = f.outputImage,
              let result = context.createCGImage(out, from: input.extent, format: .RGBA8, colorSpace: ImageIOUtil.srgb) else { return image }
        cache.setObject(Entry(source: image, filtered: result), forKey: key as NSString, cost: result.width * result.height * 4)
        return result
    }
}
