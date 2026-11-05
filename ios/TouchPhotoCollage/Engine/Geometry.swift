import Foundation

/// Axis-aligned rectangle with edges `l, t, r, b`. Used both for normalised (0...1) coordinates and for pixels or
/// points; the surrounding API says which. Pure Swift (no UIKit) so it is unit-testable.
struct FRect: Equatable, Hashable {
    var l: Double
    var t: Double
    var r: Double
    var b: Double

    init(_ l: Double, _ t: Double, _ r: Double, _ b: Double) {
        self.l = l; self.t = t; self.r = r; self.b = b
    }

    var w: Double { r - l }
    var h: Double { b - t }
    var cx: Double { (l + r) / 2 }
    var cy: Double { (t + b) / 2 }
    var area: Double { w * h }

    /// Rotate 90 degrees clockwise inside the unit square.
    func rotatedCw() -> FRect { FRect(1 - b, l, 1 - t, r) }

    /// Mirror left-right inside the unit square.
    func mirroredH() -> FRect { FRect(1 - r, t, 1 - l, b) }

    func union(_ o: FRect) -> FRect { FRect(min(l, o.l), min(t, o.t), max(r, o.r), max(b, o.b)) }

    func intersect(_ o: FRect) -> FRect? {
        let nl = max(l, o.l), nt = max(t, o.t), nr = min(r, o.r), nb = min(b, o.b)
        return (nr > nl && nb > nt) ? FRect(nl, nt, nr, nb) : nil
    }

    /// True when the two rectangles share more than `eps` of area on both axes.
    func overlaps(_ o: FRect, eps: Double = 1e-4) -> Bool {
        min(r, o.r) - max(l, o.l) > eps && min(b, o.b) - max(t, o.t) > eps
    }

    func contains(x: Double, y: Double) -> Bool { x >= l && x <= r && y >= t && y <= b }

    static let unit = FRect(0, 0, 1, 1)

    var cgRect: CGRect { CGRect(x: l, y: t, width: w, height: h) }
}

extension Array {
    /// Stable sort (Kotlin's `sortedBy` is stable; Swift's `sorted` does not promise it).
    func stableSorted<K: Comparable>(by key: (Element) -> K) -> [Element] {
        enumerated().sorted { a, b in
            let ka = key(a.element), kb = key(b.element)
            return ka != kb ? ka < kb : a.offset < b.offset
        }.map { $0.element }
    }
}
