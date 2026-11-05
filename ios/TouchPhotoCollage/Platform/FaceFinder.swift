import Foundation
import Vision
import CoreGraphics

/// Finds face boxes in a photo. Runs fully on device (Apple's Vision framework): no network, no identity recognition.
protocol FaceFinder: Sendable {
    /// Face boxes in upright (EXIF-applied) normalised coordinates, or nil if detection is unavailable/failed.
    func find(ref: PhotoRef, mediaDir: URL) -> [FRect]?
}

struct VisionFaceFinder: FaceFinder {
    func find(ref: PhotoRef, mediaDir: URL) -> [FRect]? {
        guard let image = ImageIOUtil.decodeUpright(url: mediaDir.appendingPathComponent(ref.file), maxSide: 1280) else { return nil }
        let request = VNDetectFaceRectanglesRequest()
        #if targetEnvironment(simulator)
        request.usesCPUOnly = true
        #endif
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            return nil // unreliable/unavailable: caller falls back to centre cropping
        }
        let results = request.results ?? []
        return results.compactMap { obs -> FRect? in
            // Vision boxes are normalised with the origin at the bottom-left; flip to top-left.
            let b = obs.boundingBox
            // Boxes hug the face; grow slightly so the head/hair is kept in frame.
            let padX = Double(b.width) * 0.12
            let padTop = Double(b.height) * 0.28
            let padBottom = Double(b.height) * 0.08
            let top = 1 - Double(b.maxY)
            let bottom = 1 - Double(b.minY)
            func c(_ v: Double) -> Double { min(max(v, 0), 1) }
            let r = FRect(c(Double(b.minX) - padX), c(top - padTop), c(Double(b.maxX) + padX), c(bottom + padBottom))
            return (Double(b.width) > 0.06 && r.w > 0.01 && r.h > 0.01) ? r : nil
        }
    }
}
