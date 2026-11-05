import Foundation

/// A set of cells that exactly tiles the unit square. Photos are assigned to cells in list order.
struct LayoutTemplate: Equatable {
    var id: String
    var name: String
    var cells: [FRect]
    var count: Int { cells.count }
}

/// Aspect ratio of the output canvas, as an integer ratio so presets stay exact.
struct CanvasSpec: Equatable {
    var ratioW: Int
    var ratioH: Int
    var label: String

    init(_ w: Int, _ h: Int, label: String? = nil) {
        ratioW = w; ratioH = h; self.label = label ?? "\(w):\(h)"
    }

    var aspect: Double { Double(ratioW) / Double(ratioH) }

    func sameRatio(_ o: CanvasSpec) -> Bool { ratioW == o.ratioW && ratioH == o.ratioH }

    static let square = CanvasSpec(1, 1)
    static let portrait4x5 = CanvasSpec(4, 5)
    static let portrait3x4 = CanvasSpec(3, 4)
    static let portrait2x3 = CanvasSpec(2, 3)
    static let story9x16 = CanvasSpec(9, 16)
    static let landscape4x3 = CanvasSpec(4, 3)
    static let landscape3x2 = CanvasSpec(3, 2)
    static let wide16x9 = CanvasSpec(16, 9)

    static let presets: [CanvasSpec] = [
        square, portrait4x5, portrait3x4, portrait2x3, story9x16, landscape4x3, landscape3x2, wide16x9,
    ]

    static func custom(_ w: Int, _ h: Int) -> CanvasSpec {
        CanvasSpec(min(max(w, 1), 99), min(max(h, 1), 99))
    }

    /// Friendly name used by the canvas-shape chips.
    var friendlyName: String {
        switch (ratioW, ratioH) {
        case (1, 1): return "Square 1:1"
        case (4, 5): return "Portrait 4:5"
        case (3, 4): return "Portrait 3:4"
        case (2, 3): return "Tall 2:3"
        case (9, 16): return "Story 9:16"
        case (4, 3): return "Wide 4:3"
        case (3, 2): return "Wide 3:2"
        case (16, 9): return "Cinema 16:9"
        default: return label
        }
    }
}

/// Resolves a normalised layout into pixel rectangles with margin and spacing.
enum LayoutEngine {
    private static let edge = 1e-4

    /// - margin: outer margin in pixels. spacing: gap between neighbouring cells in pixels.
    static func cellRects(_ layout: LayoutTemplate, canvasW: Double, canvasH: Double, margin: Double, spacing: Double) -> [FRect] {
        let innerW = max(canvasW - 2 * margin, 1)
        let innerH = max(canvasH - 2 * margin, 1)
        let half = spacing / 2
        return layout.cells.map { c in
            var l = margin + c.l * innerW
            var t = margin + c.t * innerH
            var r = margin + c.r * innerW
            var b = margin + c.b * innerH
            if c.l > edge { l += half }
            if c.t > edge { t += half }
            if c.r < 1 - edge { r -= half }
            if c.b < 1 - edge { b -= half }
            // never collapse: keep at least 1px even for absurd spacing
            if r - l < 1 { let m = (l + r) / 2; l = m - 0.5; r = m + 0.5 }
            if b - t < 1 { let m = (t + b) / 2; t = m - 0.5; b = m + 0.5 }
            return FRect(l, t, r, b)
        }
    }

    /// Spacing, margin and radius fractions are relative to the shorter canvas side.
    static func unit(_ canvasW: Double, _ canvasH: Double) -> Double { min(canvasW, canvasH) }

    /// Output size in pixels for a long side.
    static func sizeForLongSide(_ spec: CanvasSpec, longSide: Int) -> (Int, Int) {
        let a = spec.aspect
        if a >= 1 { return (longSide, max(Int((Double(longSide) / a).rounded()), 1)) }
        return (max(Int((Double(longSide) * a).rounded()), 1), longSide)
    }
}

/// Exact port of `java.util.Random` so "Artistic" layouts are identical on Android and iOS for a given seed.
struct JavaRandom {
    private var seed: Int64
    private static let mask: Int64 = (1 << 48) - 1

    init(seed: Int64) { self.seed = (seed ^ 0x5DEECE66D) & JavaRandom.mask }

    mutating func next(_ bits: Int) -> Int32 {
        seed = (seed &* 0x5DEECE66D &+ 0xB) & JavaRandom.mask
        return Int32(truncatingIfNeeded: seed >> Int64(48 - bits))
    }

    mutating func nextInt(_ bound: Int) -> Int {
        var r = next(31)
        let m = Int32(bound - 1)
        if (Int32(bound) & m) == 0 {
            r = Int32(truncatingIfNeeded: (Int64(bound) &* Int64(r)) >> 31)
        } else {
            var u = r
            while true {
                r = u % Int32(bound)
                if u &- r &+ m >= 0 { break }
                u = next(31)
            }
        }
        return Int(r)
    }

    mutating func nextBoolean() -> Bool { next(1) != 0 }

    /// Uniform in 0..<1 with 24 bits, like Java's `nextFloat`.
    mutating func nextFloat() -> Double { Double(Float(next(24)) / Float(1 << 24)) }
}

/// Generates tilings for any photo count. All results tile the unit square exactly (verified by tests).
enum LayoutGenerator {
    private static func distribute(_ n: Int, _ parts: Int) -> [Int] {
        let base = n / parts
        let extra = n % parts
        return (0..<parts).map { base + ($0 < extra ? 1 : 0) }
    }

    /// Horizontal rows; each row's cells share its width equally.
    static func rows(_ n: Int, _ rowCount: Int, name: String? = nil, id: String? = nil) -> LayoutTemplate {
        let counts = distribute(n, rowCount)
        var cells: [FRect] = []
        var y = 0.0
        for (ri, k) in counts.enumerated() {
            let y2 = ri == rowCount - 1 ? 1.0 : Double(ri + 1) / Double(rowCount)
            for i in 0..<k {
                cells.append(FRect(Double(i) / Double(k), y, i == k - 1 ? 1.0 : Double(i + 1) / Double(k), y2))
            }
            y = y2
        }
        return LayoutTemplate(id: id ?? "rows-\(n)-\(rowCount)", name: name ?? "\(rowCount) rows", cells: cells)
    }

    /// Grid with `cols` columns; the last row is stretched so the whole canvas is filled.
    static func gridWithColumns(_ n: Int, _ cols: Int) -> LayoutTemplate {
        let c = min(max(cols, 1), max(n, 1))
        let rowCount = (n + c - 1) / c
        return rows(n, rowCount, name: "\(c) columns", id: "grid-\(n)-c\(c)")
    }

    static func heroLeft(_ n: Int) -> LayoutTemplate {
        var cells = [FRect(0, 0, 0.6, 1)]
        let k = n - 1
        for i in 0..<k {
            cells.append(FRect(0.6, Double(i) / Double(k), 1, i == k - 1 ? 1.0 : Double(i + 1) / Double(k)))
        }
        return LayoutTemplate(id: "hero-left-\(n)", name: "Feature left", cells: cells)
    }

    static func heroTop(_ n: Int) -> LayoutTemplate {
        var cells = [FRect(0, 0, 1, 0.58)]
        let k = n - 1
        for i in 0..<k {
            cells.append(FRect(Double(i) / Double(k), 0.58, i == k - 1 ? 1.0 : Double(i + 1) / Double(k), 1))
        }
        return LayoutTemplate(id: "hero-top-\(n)", name: "Feature top", cells: cells)
    }

    /// Five-photo pinwheel with a small centre square.
    static func pinwheel5() -> LayoutTemplate {
        LayoutTemplate(id: "pinwheel-5", name: "Pinwheel", cells: [
            FRect(0, 0, 0.6, 0.4), FRect(0.6, 0, 1, 0.6), FRect(0.4, 0.6, 1, 1),
            FRect(0, 0.4, 0.4, 1), FRect(0.4, 0.4, 0.6, 0.6),
        ])
    }

    /// "Artistic" unequal mosaic from recursive splits; deterministic for a given `seed`.
    static func mosaic(_ n: Int, seed: Int) -> LayoutTemplate {
        var rnd = JavaRandom(seed: Int64(seed) &* 7919 &+ Int64(n) &* 104729)
        var parts: [FRect] = [.unit]
        var guardCount = 0
        while parts.count < n && guardCount < 10_000 {
            guardCount += 1
            // split a large cell: weighted towards big areas so sizes vary but none is tiny
            var idx = 0
            var best = -Double.greatestFiniteMagnitude
            for i in parts.indices {
                let score = parts[i].area * (0.6 + rnd.nextFloat() * 0.8)
                if score > best { best = score; idx = i }
            }
            let p = parts[idx]
            let vertical = abs(p.w - p.h) < 0.05 ? rnd.nextBoolean() : p.w > p.h
            let ratio = 0.36 + rnd.nextFloat() * 0.28
            let a: FRect
            let b: FRect
            if vertical {
                let x = p.l + p.w * ratio
                a = FRect(p.l, p.t, x, p.b); b = FRect(x, p.t, p.r, p.b)
            } else {
                let y = p.t + p.h * ratio
                a = FRect(p.l, p.t, p.r, y); b = FRect(p.l, y, p.r, p.b)
            }
            parts.remove(at: idx)
            parts.append(a); parts.append(b)
        }
        let sorted = parts.stableSorted { c in (c.t * 20 + 0.5).rounded(.down) * 1000 + c.l }
        return LayoutTemplate(id: "mosaic-\(n)-\(seed)", name: "Artistic \(seed + 1)", cells: sorted)
    }

    private static let minCell = 0.07

    /// All sensible layouts for `n` photos, best-looking defaults first.
    static func candidates(_ n: Int) -> [LayoutTemplate] {
        precondition(n >= 1, "need at least one photo")
        if n == 1 { return [LayoutTemplate(id: "single", name: "Single", cells: [.unit])] }
        var out: [LayoutTemplate] = []
        let maxRows = min(n, 8)
        let sq = Double(n).squareRoot()
        for r in Array(1...maxRows).stableSorted(by: { abs(Double($0) - sq) }) {
            let name: String
            if r == 1 { name = "Side by side" } else if r == n { name = "Stacked" } else { name = "\(r) rows" }
            out.append(rows(n, r, name: name))
        }
        if n <= 8 {
            for c in Array(2...max(2, min(n, 6))).stableSorted(by: { abs(Double($0) - sq) }) where c <= n {
                out.append(columnsLayout(n, c, name: c == n ? "Columns" : "\(c) columns"))
            }
        }
        if n >= 3 { out.append(heroLeft(n)); out.append(heroTop(n)) }
        if n == 5 { out.append(pinwheel5()) }
        if n >= 3 { for s in 0...2 { out.append(mosaic(n, seed: s)) } }
        // drop layouts that would create slivers too thin to hold a photo
        var seen = Set<String>()
        let distinct = out.filter { seen.insert($0.id).inserted }
        let usable = distinct.filter { l in l.cells.allSatisfy { $0.w >= minCell && $0.h >= minCell } }
        return usable.isEmpty ? [gridWithColumns(n, Int(sq.rounded(.up)))] : usable
    }

    private static func columnsLayout(_ n: Int, _ c: Int, name: String) -> LayoutTemplate {
        let counts = distribute(n, c)
        var cells: [FRect] = []
        for (ci, k) in counts.enumerated() {
            let x1 = Double(ci) / Double(c)
            let x2 = ci == c - 1 ? 1.0 : Double(ci + 1) / Double(c)
            for i in 0..<k {
                cells.append(FRect(x1, Double(i) / Double(k), x2, i == k - 1 ? 1.0 : Double(i + 1) / Double(k)))
            }
        }
        let ordered = cells.stableSorted { c in (c.t * 100).rounded(.toNearestOrAwayFromZero) * 1000 + c.l }
        return LayoutTemplate(id: "cols-\(n)-\(c)", name: name, cells: ordered)
    }

    /// Sum over cells of |ln(cell aspect / photo aspect)|: how much cropping a layout would force.
    static func cropCost(_ layout: LayoutTemplate, canvasAspect: Double, photoAspects: [Double]) -> Double {
        var cost = 0.0
        for (i, c) in layout.cells.enumerated() {
            guard i < photoAspects.count else { continue }
            let ca = c.w / c.h * canvasAspect
            cost += abs(log(ca / photoAspects[i]))
        }
        return cost / Double(layout.count)
    }

    /// Automatic choice: the layout + canvas ratio pair that crops the given photos least.
    static func auto(photoAspects: [Double], layouts: [LayoutTemplate]? = nil, canvases: [CanvasSpec] = CanvasSpec.presets) -> (LayoutTemplate, CanvasSpec) {
        let ls = layouts ?? candidates(photoAspects.count)
        var best: (LayoutTemplate, CanvasSpec)? = nil
        var bestScore = Double.greatestFiniteMagnitude
        for (li, l) in ls.enumerated() {
            for c in canvases {
                // small tie-breaks: prefer earlier (more regular) layouts and friendly social ratios
                let extreme = Double(c.ratioH) > Double(c.ratioW) * 1.7 || Double(c.ratioW) > Double(c.ratioH) * 1.7
                let score = cropCost(l, canvasAspect: c.aspect, photoAspects: photoAspects) + Double(li) * 0.004 + (extreme ? 0.03 : 0)
                if score < bestScore { bestScore = score; best = (l, c) }
            }
        }
        return best!
    }
}
