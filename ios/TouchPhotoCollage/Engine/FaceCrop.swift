import Foundation

/// Crop state for one cell (display space).
struct CropState: Equatable {
    var zoom: Double
    var cx: Double
    var cy: Double
}

/// One photo as seen by the face-aware crop logic.
struct FaceInput {
    /// Aspect (w/h) of the *display* image.
    var imgAspect: Double
    /// Faces in display space, normalised. Empty = none found, crop falls back to the centre.
    var faces: [FRect]
    /// Pixel aspect of the cell the photo will fill.
    var cellAspect: Double
    var fit = false
}

/// Face-aware crop planning. Pure maths, no ML: detection is done elsewhere and only boxes arrive here.
/// Zoom is always uniform (the visible region keeps the cell's aspect ratio), so faces are never distorted.
enum FaceCrop {
    /// Vertical position of the face centre inside the cell that looks natural for portraits.
    static let targetY = 0.40
    static let desiredFaceHeight = 0.34
    private static let maxAlignZoom = 6.0

    /// Largest face by area (the subject).
    static func primary(_ faces: [FRect]) -> FRect? {
        var best: FRect? = nil
        for f in faces where best == nil || f.area > best!.area { best = f }
        return best
    }

    /// Smallest crop that keeps every face visible: just centre on the faces, zoom 1.
    static func smart(_ input: FaceInput) -> CropState {
        if input.faces.isEmpty || input.fit { return CropState(zoom: 1, cx: 0.5, cy: 0.5) }
        let all = input.faces.dropFirst().reduce(input.faces[0]) { $0.union($1) }
        let region = CropMath.region(imgAspect: input.imgAspect, cellAspect: input.cellAspect, zoom: 1, cx: 0.5, cy: 0.5, fit: false)
        // put the subject slightly above centre if there is room vertically
        let cy = region.visH < 1 ? all.cy + (0.5 - targetY) * region.visH : 0.5
        return clampState(input, CropState(zoom: 1, cx: all.cx, cy: cy))
    }

    /// Fraction of the cell height the main face occupies at zoom 1.
    static func naturalFaceHeight(_ input: FaceInput) -> Double? {
        guard let f = primary(input.faces) else { return nil }
        let region = CropMath.region(imgAspect: input.imgAspect, cellAspect: input.cellAspect, zoom: 1, cx: 0.5, cy: 0.5, fit: input.fit)
        return f.h / region.visH
    }

    /// Align several photos so their main faces have (nearly) the same size and sit at the same height.
    /// Photos without a face keep a centre crop. Returns one `CropState` per input.
    static func align(_ inputs: [FaceInput]) -> [CropState] {
        let natural: [Double?] = inputs.map { $0.fit ? nil : naturalFaceHeight($0) }
        let known = natural.compactMap { $0 }
        if known.isEmpty { return inputs.map { _ in CropState(zoom: 1, cx: 0.5, cy: 0.5) } }
        // The shared face height must be reachable (zoom >= 1) for every photo and not need absurd zoom.
        let lo = known.max()!
        let hi = known.min()! * maxAlignZoom
        let target = lo > hi ? lo : min(max(desiredFaceHeight, lo), hi)
        return inputs.enumerated().map { i, input in
            let nat = natural[i]
            let face = primary(input.faces)
            guard let nat = nat, let face = face else {
                return input.faces.isEmpty ? CropState(zoom: 1, cx: 0.5, cy: 0.5) : smart(input)
            }
            let zoom = min(max(target / nat, 1), maxAlignZoom)
            let region = CropMath.region(imgAspect: input.imgAspect, cellAspect: input.cellAspect, zoom: zoom, cx: 0.5, cy: 0.5, fit: false)
            // face centre should land at targetY of the cell height
            let cy = face.cy + (0.5 - targetY) * region.visH
            return clampState(input, CropState(zoom: zoom, cx: face.cx, cy: cy))
        }
    }

    private static func clampState(_ input: FaceInput, _ s: CropState) -> CropState {
        let r = CropMath.region(imgAspect: input.imgAspect, cellAspect: input.cellAspect, zoom: s.zoom, cx: s.cx, cy: s.cy, fit: input.fit)
        return CropState(zoom: CropMath.clampZoom(s.zoom), cx: r.rect.cx, cy: r.rect.cy)
    }

    /// True if the faces lie fully inside the region described by `state`.
    static func facesVisible(_ input: FaceInput, _ state: CropState) -> Bool {
        let r = CropMath.region(imgAspect: input.imgAspect, cellAspect: input.cellAspect, zoom: state.zoom, cx: state.cx, cy: state.cy, fit: input.fit).rect
        return input.faces.allSatisfy { f in f.l >= r.l - 1e-4 && f.r <= r.r + 1e-4 && f.t >= r.t - 1e-4 && f.b <= r.b + 1e-4 }
    }
}
