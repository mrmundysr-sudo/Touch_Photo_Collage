import Foundation

/// Size of an image after orientation has been applied.
struct DisplaySize: Equatable {
    var w: Int
    var h: Int
    var aspect: Double { Double(w) / Double(h) }
}

/// Orientation maths shared by renderer, face logic and tests.
///
/// Three stages turn raw decoded pixels into the "display space" in which every crop, face and gesture lives:
///  1. EXIF orientation (values 1...8) so the photo is upright as the camera intended,
///  2. user rotation in clockwise quarter turns,
///  3. optional left/right mirroring.
enum Orientation {
    static func floorMod(_ x: Int, _ m: Int) -> Int { ((x % m) + m) % m }

    static func exifSwapsAxes(_ exif: Int) -> Bool { (5...8).contains(exif) }

    /// Display size for an image of raw size `w` x `h`.
    static func displaySize(_ w: Int, _ h: Int, exif: Int, quarterTurns: Int) -> DisplaySize {
        let swap = exifSwapsAxes(exif) != (floorMod(quarterTurns, 4) % 2 == 1)
        return swap ? DisplaySize(w: h, h: w) : DisplaySize(w: w, h: h)
    }

    /// Raw pixel coordinates (0...w, 0...h) -> upright (EXIF-applied) coordinates.
    static func exifAffine(_ w: Double, _ h: Double, exif: Int) -> Affine {
        switch exif {
        case 2: return Affine(a: -1, tx: w)
        case 3: return Affine(a: -1, d: -1, tx: w, ty: h)
        case 4: return Affine(d: -1, ty: h)
        case 5: return Affine(a: 0, b: 1, c: 1, d: 0)
        case 6: return Affine(a: 0, b: 1, c: -1, d: 0, tx: h)
        case 7: return Affine(a: 0, b: -1, c: -1, d: 0, tx: h, ty: w)
        case 8: return Affine(a: 0, b: -1, c: 1, d: 0, ty: w)
        default: return .identity
        }
    }

    /// Clockwise quarter turns for an image of size `w` x `h` (the size *before* the turn).
    static func rotateAffine(_ w: Double, _ h: Double, quarterTurns: Int) -> Affine {
        switch floorMod(quarterTurns, 4) {
        case 1: return Affine(a: 0, b: 1, c: -1, d: 0, tx: h)
        case 2: return Affine(a: -1, d: -1, tx: w, ty: h)
        case 3: return Affine(a: 0, b: -1, c: 1, d: 0, ty: w)
        default: return .identity
        }
    }

    /// Raw pixels -> display space (pixel units of the display image).
    static func totalAffine(rawW: Int, rawH: Int, exif: Int, quarterTurns: Int, mirror: Bool) -> Affine {
        let upright = exifAffine(Double(rawW), Double(rawH), exif: exif)
        let s1 = exifSwapsAxes(exif) ? DisplaySize(w: rawH, h: rawW) : DisplaySize(w: rawW, h: rawH)
        let rot = rotateAffine(Double(s1.w), Double(s1.h), quarterTurns: quarterTurns)
        let disp = displaySize(rawW, rawH, exif: exif, quarterTurns: quarterTurns)
        var m = upright.then(rot)
        if mirror { m = m.then(Affine(a: -1, tx: Double(disp.w))) }
        return m
    }

    /// Move a rectangle given in upright (EXIF-applied) normalised coordinates into display space.
    static func toDisplay(_ r: FRect, quarterTurns: Int, mirror: Bool) -> FRect {
        var out = r
        for _ in 0..<floorMod(quarterTurns, 4) { out = out.rotatedCw() }
        if mirror { out = out.mirroredH() }
        return out
    }
}
