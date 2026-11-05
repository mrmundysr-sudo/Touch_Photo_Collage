import Foundation

/// Crop geometry. Everything is in normalised display-space coordinates of the photo (0...1 on both axes).
///
/// A cell shows a "visible region" of the photo. The region always has exactly the cell's pixel aspect ratio, so the
/// photo is only ever scaled uniformly: faces and proportions are never distorted.
///
///  * Fill mode (cover): the region is inside the photo, the cell is completely covered, edges may be cropped.
///  * Fit mode (contain / "never crop"): at zoom 1 the region is larger than the photo and the whole photo is
///    visible with bars; zooming in crops as in fill mode.
enum CropMath {
    static let minZoom = 1.0
    static let maxZoom = 8.0

    struct Region {
        var rect: FRect
        var visW: Double
        var visH: Double
    }

    static func clampZoom(_ z: Double) -> Double { min(max(z, minZoom), maxZoom) }

    /// Region size at zoom 1 (normalised units).
    static func baseSize(imgAspect: Double, cellAspect: Double, fit: Bool) -> (Double, Double) {
        let wide = imgAspect > cellAspect
        if !fit {
            return wide ? (cellAspect / imgAspect, 1) : (1, imgAspect / cellAspect)
        } else {
            return wide ? (1, imgAspect / cellAspect) : (cellAspect / imgAspect, 1)
        }
    }

    static func region(imgAspect: Double, cellAspect: Double, zoom: Double, cx: Double, cy: Double, fit: Bool) -> Region {
        let (bw, bh) = baseSize(imgAspect: imgAspect, cellAspect: cellAspect, fit: fit)
        let z = clampZoom(zoom)
        let vw = bw / z
        let vh = bh / z
        let ccx = clampCenter(cx, vis: vw)
        let ccy = clampCenter(cy, vis: vh)
        return Region(rect: FRect(ccx - vw / 2, ccy - vh / 2, ccx + vw / 2, ccy + vh / 2), visW: vw, visH: vh)
    }

    /// Keep the region inside the photo; if it is larger than the photo (fit mode) it stays centred.
    static func clampCenter(_ c: Double, vis: Double) -> Double {
        vis >= 1 ? 0.5 : min(max(c, vis / 2), 1 - vis / 2)
    }

    /// Part of the photo inside the region.
    static func photoPart(_ region: Region) -> FRect { region.rect.intersect(.unit) ?? .unit }

    /// Where `photoPart` lands inside the cell rectangle `cell` (pixels).
    static func destRect(_ region: Region, cell: FRect) -> FRect {
        let p = photoPart(region)
        let sx = cell.w / region.visW
        let sy = cell.h / region.visH
        return FRect(
            cell.l + (p.l - region.rect.l) * sx,
            cell.t + (p.t - region.rect.t) * sy,
            cell.l + (p.r - region.rect.l) * sx,
            cell.t + (p.b - region.rect.t) * sy
        )
    }

    /// Result of dragging the photo by `dx`/`dy` screen pixels inside a cell of `cellW` x `cellH` pixels.
    static func pan(
        imgAspect: Double, cellW: Double, cellH: Double, zoom: Double, cx: Double, cy: Double, fit: Bool,
        dx: Double, dy: Double
    ) -> (Double, Double) {
        let r = region(imgAspect: imgAspect, cellAspect: cellW / cellH, zoom: zoom, cx: cx, cy: cy, fit: fit)
        let ncx = clampCenter(r.rect.cx - dx / cellW * r.visW, vis: r.visW)
        let ncy = clampCenter(r.rect.cy - dy / cellH * r.visH, vis: r.visH)
        return (ncx, ncy)
    }

    /// Zoom about a screen point so the photo content under the fingers stays put.
    /// `fx`/`fy` are the focal point within the cell, 0...1. Returns (zoom, cx, cy).
    static func zoomAbout(
        imgAspect: Double, cellAspect: Double, zoom: Double, cx: Double, cy: Double, fit: Bool,
        newZoom: Double, fx: Double, fy: Double
    ) -> (Double, Double, Double) {
        let r = region(imgAspect: imgAspect, cellAspect: cellAspect, zoom: zoom, cx: cx, cy: cy, fit: fit)
        let z2 = clampZoom(newZoom)
        let (bw, bh) = baseSize(imgAspect: imgAspect, cellAspect: cellAspect, fit: fit)
        let vw2 = bw / z2
        let vh2 = bh / z2
        let px = r.rect.l + fx * r.visW
        let py = r.rect.t + fy * r.visH
        let ncx = clampCenter(px - (fx - 0.5) * vw2, vis: vw2)
        let ncy = clampCenter(py - (fy - 0.5) * vh2, vis: vh2)
        return (z2, ncx, ncy)
    }

    /// Largest power-of-two decode sample so the decoded image still has at least the needed resolution.
    static func sampleFor(_ destPxPerSourcePx: Double) -> Int {
        if destPxPerSourcePx <= 0 || destPxPerSourcePx >= 1 { return 1 }
        var s = 1
        while Double(2 * s) <= 1 / destPxPerSourcePx && s < 64 { s *= 2 }
        return max(1, min(64, s))
    }
}
