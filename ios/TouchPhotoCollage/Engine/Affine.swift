import Foundation
import CoreGraphics

/// 2D affine map: x' = a*x + c*y + tx ; y' = b*x + d*y + ty (same convention as CGAffineTransform).
struct Affine: Equatable {
    var a = 1.0, b = 0.0, c = 0.0, d = 1.0, tx = 0.0, ty = 0.0

    init(a: Double = 1, b: Double = 0, c: Double = 0, d: Double = 1, tx: Double = 0, ty: Double = 0) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty
    }

    func mapX(_ x: Double, _ y: Double) -> Double { a * x + c * y + tx }
    func mapY(_ x: Double, _ y: Double) -> Double { b * x + d * y + ty }

    /// Returns the map "first self, then `next`".
    func then(_ next: Affine) -> Affine {
        Affine(
            a: next.a * a + next.c * b,
            b: next.b * a + next.d * b,
            c: next.a * c + next.c * d,
            d: next.b * c + next.d * d,
            tx: next.a * tx + next.c * ty + next.tx,
            ty: next.b * tx + next.d * ty + next.ty
        )
    }

    var cg: CGAffineTransform { CGAffineTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty) }

    static let identity = Affine()
}
