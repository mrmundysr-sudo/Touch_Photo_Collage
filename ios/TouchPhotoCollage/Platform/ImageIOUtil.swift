import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// Decoding helpers built on ImageIO. Images are decoded *without* orientation applied ("raw" pixels), exactly like
/// the Android `BitmapFactory` path, so the engine's orientation maths (EXIF + rotation + mirror) applies unchanged.
enum ImageIOUtil {
    struct Info: Equatable {
        var width: Int
        var height: Int
        var exif: Int
    }

    static let srgb: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    static func info(at url: URL) -> Info? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(src) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, w > 0, h > 0 else { return nil }
        let o = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return Info(width: w, height: h, exif: (1...8).contains(o) ? o : 1)
    }

    /// Raw (un-oriented) pixels, reduced by a power-of-two `sample`.
    static func decodeRaw(url: URL, width: Int, height: Int, sample: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        if sample <= 1 {
            return CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: false,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, max(width, height) / sample),
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    /// Upright (EXIF-applied) image whose longest side is at most `maxSide`. For thumbnails and face detection.
    static func decodeUpright(url: URL, maxSide: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    static func encode(_ image: CGImage, as type: UTType, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        var props: [CFString: Any] = [:]
        if type == .jpeg { props[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    static func write(_ image: CGImage, to url: URL, as type: UTType, quality: Double) throws -> Int64 {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw ExportError.encodingFailed
        }
        var props: [CFString: Any] = [:]
        if type == .jpeg { props[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ExportError.encodingFailed }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }
}

enum ExportError: LocalizedError {
    case encodingFailed
    case renderFailed
    case photosDenied
    case photosUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .encodingFailed: return "The image could not be encoded."
        case .renderFailed: return "Not enough memory for that size. Try Standard quality."
        case .photosDenied: return "Photos access is turned off."
        case .photosUnavailable(let m): return m
        }
    }
}
