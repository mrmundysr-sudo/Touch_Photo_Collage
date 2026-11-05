import Foundation

/// 4x5 colour matrices in `ColorMatrix` layout (row-major, offsets in 0...255), kept as plain arrays so they can be
/// unit-tested without any imaging framework. The renderer turns them into Core Image `CIColorMatrix` filters.
enum ColorMath {
    private static let identityMatrix: [Double] = [
        1, 0, 0, 0, 0,
        0, 1, 0, 0, 0,
        0, 0, 1, 0, 0,
        0, 0, 0, 1, 0,
    ]

    static func identity() -> [Double] { identityMatrix }

    static func isIdentity(_ m: [Double]) -> Bool {
        m.indices.allSatisfy { abs(m[$0] - identityMatrix[$0]) < 1e-4 }
    }

    /// Result of applying `a` first and then `b`.
    static func concat(_ a: [Double], _ b: [Double]) -> [Double] {
        var out = [Double](repeating: 0, count: 20)
        for row in 0..<4 {
            for col in 0..<5 {
                var v = 0.0
                for k in 0..<4 { v += b[row * 5 + k] * a[k * 5 + col] }
                if col == 4 { v += b[row * 5 + 4] }
                out[row * 5 + col] = v
            }
        }
        return out
    }

    static func brightness(_ b: Double) -> [Double] {
        var m = identity()
        let o = b * 0.4 * 255
        m[4] = o; m[9] = o; m[14] = o
        return m
    }

    static func contrast(_ c: Double) -> [Double] {
        let s = c >= 0 ? 1 + c * 0.8 : 1 + c * 0.6
        let o = 127.5 * (1 - s)
        return [
            s, 0, 0, 0, o,
            0, s, 0, 0, o,
            0, 0, s, 0, o,
            0, 0, 0, 1, 0,
        ]
    }

    /// `s` = 1 is neutral, 0 is greyscale, 2 is double saturation.
    static func saturation(_ s: Double) -> [Double] {
        let lr = 0.2126, lg = 0.7152, lb = 0.0722
        let inv = 1 - s
        return [
            lr * inv + s, lg * inv, lb * inv, 0, 0,
            lr * inv, lg * inv + s, lb * inv, 0, 0,
            lr * inv, lg * inv, lb * inv + s, 0, 0,
            0, 0, 0, 1, 0,
        ]
    }

    static func warmth(_ w: Double) -> [Double] {
        [
            1 + 0.22 * w, 0, 0, 0, 0,
            0, 1 + 0.04 * w, 0, 0, 0,
            0, 0, 1 - 0.22 * w, 0, 0,
            0, 0, 0, 1, 0,
        ]
    }

    private static let sepia: [Double] = [
        0.393, 0.769, 0.189, 0, 0,
        0.349, 0.686, 0.168, 0, 0,
        0.272, 0.534, 0.131, 0, 0,
        0, 0, 0, 1, 0,
    ]

    static func filter(_ type: FilterType) -> [Double] {
        switch type {
        case .none: return identity()
        case .blackWhite: return concat(saturation(0), contrast(0.12))
        case .sepia: return sepia
        case .vintage:
            var m = [saturation(0.65), warmth(0.5), contrast(-0.18), brightness(0.06)].dropFirst().reduce(saturation(0.65)) { concat($0, $1) }
            m[14] += 8 // slightly lifted, cool shadows
            return m
        case .fade: return concat(contrast(-0.25), concat(saturation(0.85), brightness(0.08)))
        case .vivid: return concat(saturation(1.45), contrast(0.12))
        case .cool: return warmth(-0.6)
        case .warm: return warmth(0.6)
        }
    }

    /// Full matrix for a cell: filter first, then the user's adjustments.
    static func forCell(_ adj: Adjustments, _ filter: FilterType) -> [Double] {
        var m = Self.filter(filter)
        if adj.brightness != 0 { m = concat(m, brightness(adj.brightness)) }
        if adj.contrast != 0 { m = concat(m, contrast(adj.contrast)) }
        if adj.saturation != 0 { m = concat(m, saturation(1 + adj.saturation)) }
        if adj.warmth != 0 { m = concat(m, warmth(adj.warmth)) }
        return m
    }

    /// Applies a matrix to one RGBA colour (0...255 channels) the way the GPU/CPU filter does, clamped.
    static func apply(_ m: [Double], r: Double, g: Double, b: Double, a: Double = 255) -> (Double, Double, Double, Double) {
        func ch(_ row: Int) -> Double {
            min(max(m[row * 5] * r + m[row * 5 + 1] * g + m[row * 5 + 2] * b + m[row * 5 + 3] * a + m[row * 5 + 4], 0), 255)
        }
        return (ch(0), ch(1), ch(2), ch(3))
    }
}

/// Simple unsharp-mask sharpening on tightly packed 8-bit RGBA pixels.
enum Sharpen {
    /// - amount: 0 = unchanged, 1 = strong. Returns a new array; alpha is preserved.
    static func apply(_ src: [UInt8], w: Int, h: Int, amount: Double) -> [UInt8] {
        if amount <= 0 || w < 3 || h < 3 { return src }
        var out = src
        let k = amount * 1.6
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let i = (y * w + x) * 4
                for c in 0..<3 {
                    var sum = 0
                    for dy in -1...1 {
                        for dx in -1...1 { sum += Int(src[i + (dy * w + dx) * 4 + c]) }
                    }
                    let v = Double(src[i + c])
                    let n = v + k * (v - Double(sum) / 9)
                    out[i + c] = UInt8(min(max(Int(n), 0), 255))
                }
            }
        }
        return out
    }
}
