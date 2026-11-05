import XCTest
@testable import TouchPhotoCollage

final class CropMathTests: XCTestCase {
    private let eps = 1e-3

    private func pixelAspect(_ r: CropMath.Region, _ imgAspect: Double) -> Double { r.visW / r.visH * imgAspect }

    func testFillRegionHasCellAspectAndStaysInsidePhoto() {
        for img in [0.5, 0.75, 1, 1.5, 3] { for cell in [0.5, 1, 1.7] { for z in [1.0, 2, 5] {
            let r = CropMath.region(imgAspect: img, cellAspect: cell, zoom: z, cx: 0.1, cy: 0.9, fit: false)
            XCTAssertEqual(pixelAspect(r, img), cell, accuracy: 1e-3, "never distorts (img=\(img) cell=\(cell) z=\(z))")
            XCTAssertTrue(r.rect.l >= -eps && r.rect.t >= -eps && r.rect.r <= 1 + eps && r.rect.b <= 1 + eps)
        } } }
    }

    func testFitShowsWholePhotoWithoutDistortion() {
        for img in [0.5, 1, 2] { for cell in [0.6, 1, 1.8] {
            let r = CropMath.region(imgAspect: img, cellAspect: cell, zoom: 1, cx: 0.2, cy: 0.2, fit: true)
            XCTAssertEqual(pixelAspect(r, img), cell, accuracy: 1e-3)
            XCTAssertTrue(r.rect.l <= eps && r.rect.t <= eps && r.rect.r >= 1 - eps && r.rect.b >= 1 - eps, "whole photo inside region")
            let d = CropMath.destRect(r, cell: FRect(0, 0, 1000 * cell, 1000))
            XCTAssertEqual(d.w / d.h, img, accuracy: 1e-2, "photo keeps its own aspect")
        } }
    }

    func testFillDestinationIsTheWholeCell() {
        let r = CropMath.region(imgAspect: 1.5, cellAspect: 1, zoom: 1.7, cx: 0.4, cy: 0.6, fit: false)
        let d = CropMath.destRect(r, cell: FRect(10, 20, 210, 220))
        XCTAssertEqual(d.l, 10, accuracy: 1e-2); XCTAssertEqual(d.r, 210, accuracy: 1e-2)
        XCTAssertEqual(d.t, 20, accuracy: 1e-2); XCTAssertEqual(d.b, 220, accuracy: 1e-2)
    }

    func testPanIsClampedToPhotoEdges() {
        let (cx, cy) = CropMath.pan(imgAspect: 1.5, cellW: 100, cellH: 100, zoom: 2, cx: 0.5, cy: 0.5, fit: false, dx: 100000, dy: -100000)
        let r = CropMath.region(imgAspect: 1.5, cellAspect: 1, zoom: 2, cx: cx, cy: cy, fit: false)
        XCTAssertEqual(r.rect.l, 0, accuracy: eps); XCTAssertEqual(r.rect.b, 1, accuracy: eps)
    }

    func testPanMovesContentWithTheFinger() {
        // dragging the photo right by half the cell moves the visible window left by half its width
        let r0 = CropMath.region(imgAspect: 1, cellAspect: 1, zoom: 2, cx: 0.5, cy: 0.5, fit: false)
        let (cx, _) = CropMath.pan(imgAspect: 1, cellW: 200, cellH: 200, zoom: 2, cx: 0.5, cy: 0.5, fit: false, dx: 100, dy: 0)
        XCTAssertEqual(cx, r0.rect.cx - 0.5 * r0.visW, accuracy: eps)
    }

    func testZoomAboutKeepsFocalContentStill() {
        let img = 1.3, cell = 1.0
        let r0 = CropMath.region(imgAspect: img, cellAspect: cell, zoom: 1.5, cx: 0.5, cy: 0.5, fit: false)
        let (z, cx, cy) = CropMath.zoomAbout(imgAspect: img, cellAspect: cell, zoom: 1.5, cx: 0.5, cy: 0.5, fit: false, newZoom: 3, fx: 0.25, fy: 0.75)
        let r1 = CropMath.region(imgAspect: img, cellAspect: cell, zoom: z, cx: cx, cy: cy, fit: false)
        XCTAssertEqual(r0.rect.l + 0.25 * r0.visW, r1.rect.l + 0.25 * r1.visW, accuracy: eps)
        XCTAssertEqual(r0.rect.t + 0.75 * r0.visH, r1.rect.t + 0.75 * r1.visH, accuracy: eps)
    }

    func testZoomIsClamped() {
        XCTAssertEqual(CropMath.clampZoom(0.2), 1)
        XCTAssertEqual(CropMath.clampZoom(99), CropMath.maxZoom)
    }

    func testSampleSizeNeverDropsBelowNeededResolution() {
        XCTAssertEqual(CropMath.sampleFor(1.5), 1)
        XCTAssertEqual(CropMath.sampleFor(0.9), 1)
        XCTAssertEqual(CropMath.sampleFor(0.5), 2)
        XCTAssertEqual(CropMath.sampleFor(0.4), 2)
        XCTAssertEqual(CropMath.sampleFor(0.25), 4)
        for r in [0.7, 0.3, 0.11, 0.03] { XCTAssertLessThanOrEqual(r * Double(CropMath.sampleFor(r)), 1 + 1e-6) }
    }
}

final class OrientationTests: XCTestCase {
    private func map(_ a: Affine, _ x: Double, _ y: Double) -> (Double, Double) { (a.mapX(x, y), a.mapY(x, y)) }

    func testExifSixPutsRawTopLeftAtDisplayTopRight() {
        // raw 40x20, EXIF 6 = rotate 90° clockwise: raw top-left (0,0) goes to display top-right (20,0)
        let a = Orientation.totalAffine(rawW: 40, rawH: 20, exif: 6, quarterTurns: 0, mirror: false)
        let (x, y) = map(a, 0, 0)
        XCTAssertEqual(x, 20, accuracy: 1e-9); XCTAssertEqual(y, 0, accuracy: 1e-9)
        let (x2, y2) = map(a, 40, 20) // raw bottom-right -> display bottom-left
        XCTAssertEqual(x2, 0, accuracy: 1e-9); XCTAssertEqual(y2, 40, accuracy: 1e-9)
    }

    func testExifThreeIsHalfTurn() {
        let a = Orientation.totalAffine(rawW: 40, rawH: 20, exif: 3, quarterTurns: 0, mirror: false)
        let (x, y) = map(a, 0, 0)
        XCTAssertEqual(x, 40, accuracy: 1e-9); XCTAssertEqual(y, 20, accuracy: 1e-9)
    }

    func testExifTwoMirrorsHorizontally() {
        let a = Orientation.totalAffine(rawW: 40, rawH: 20, exif: 2, quarterTurns: 0, mirror: false)
        let (x, y) = map(a, 0, 5)
        XCTAssertEqual(x, 40, accuracy: 1e-9); XCTAssertEqual(y, 5, accuracy: 1e-9)
    }

    func testEveryCombinationStaysInsideDisplayBounds() {
        for exif in 1...8 { for turns in 0..<4 { for mirror in [false, true] {
            let a = Orientation.totalAffine(rawW: 40, rawH: 20, exif: exif, quarterTurns: turns, mirror: mirror)
            let d = Orientation.displaySize(40, 20, exif: exif, quarterTurns: turns)
            for (x, y) in [(0.0, 0.0), (40, 0), (0, 20), (40, 20)] {
                let (mx, my) = map(a, x, y)
                XCTAssertTrue(mx >= -1e-9 && mx <= Double(d.w) + 1e-9 && my >= -1e-9 && my <= Double(d.h) + 1e-9, "exif \(exif) turns \(turns) mirror \(mirror)")
            }
        } } }
    }

    func testFaceRectsFollowRotationAndMirrorLikePixels() {
        let face = FRect(0.1, 0.2, 0.3, 0.4)
        // one clockwise quarter turn maps (x, y) to (1 - y, x)
        let r = Orientation.toDisplay(face, quarterTurns: 1, mirror: false)
        XCTAssertEqual(r.l, 1 - 0.4, accuracy: 1e-9); XCTAssertEqual(r.r, 1 - 0.2, accuracy: 1e-9)
        XCTAssertEqual(r.t, 0.1, accuracy: 1e-9); XCTAssertEqual(r.b, 0.3, accuracy: 1e-9)
        let m = Orientation.toDisplay(face, quarterTurns: 0, mirror: true)
        XCTAssertEqual(m.l, 0.7, accuracy: 1e-9); XCTAssertEqual(m.r, 0.9, accuracy: 1e-9)
    }

    func testDisplaySizeSwapsForSideways() {
        XCTAssertEqual(Orientation.displaySize(40, 20, exif: 1, quarterTurns: 0), DisplaySize(w: 40, h: 20))
        XCTAssertEqual(Orientation.displaySize(40, 20, exif: 6, quarterTurns: 0), DisplaySize(w: 20, h: 40))
        XCTAssertEqual(Orientation.displaySize(40, 20, exif: 1, quarterTurns: 1), DisplaySize(w: 20, h: 40))
        XCTAssertEqual(Orientation.displaySize(40, 20, exif: 6, quarterTurns: 1), DisplaySize(w: 40, h: 20))
    }
}

final class LayoutTests: XCTestCase {
    private func assertTiles(_ l: LayoutTemplate, _ n: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(l.cells.count, n, "\(l.id) cell count", file: file, line: line)
        XCTAssertEqual(l.cells.reduce(0) { $0 + $1.area }, 1, accuracy: 1e-4, "\(l.id) tiles the canvas", file: file, line: line)
        for c in l.cells {
            XCTAssertTrue(c.l >= -1e-9 && c.t >= -1e-9 && c.r <= 1 + 1e-9 && c.b <= 1 + 1e-9, "\(l.id) inside canvas", file: file, line: line)
        }
        for i in l.cells.indices { for j in (i + 1)..<max(i + 1, l.cells.count) {
            XCTAssertFalse(l.cells[i].overlaps(l.cells[j]), "\(l.id) cells \(i)/\(j) overlap", file: file, line: line)
        } }
    }

    func testEveryCandidateTilesTheCanvasForAnyPhotoCount() {
        for n in 1...30 {
            let cs = LayoutGenerator.candidates(n)
            XCTAssertFalse(cs.isEmpty)
            for l in cs { assertTiles(l, n) }
        }
    }

    func testCommonCountsOfferHorizontalVerticalGridAndArtisticOptions() {
        for n in [3, 4, 5, 6] {
            let cs = LayoutGenerator.candidates(n)
            XCTAssertTrue(cs.contains { $0.id == "rows-\(n)-1" }, "side by side for \(n)")
            XCTAssertTrue(cs.contains { $0.id == "rows-\(n)-\(n)" }, "stacked for \(n)")
            XCTAssertTrue(cs.contains { $0.id.hasPrefix("mosaic") }, "artistic for \(n)")
        }
    }

    func testMosaicIsDeterministicPerSeedAndDiffersBetweenSeeds() {
        XCTAssertEqual(LayoutGenerator.mosaic(6, seed: 1), LayoutGenerator.mosaic(6, seed: 1))
        XCTAssertNotEqual(LayoutGenerator.mosaic(6, seed: 1).cells, LayoutGenerator.mosaic(6, seed: 2).cells)
        assertTiles(LayoutGenerator.mosaic(9, seed: 7), 9)
    }

    func testJavaRandomMatchesTheJdk() {
        // Well-known java.util.Random outputs, so Artistic layouts match the Android app.
        var a = JavaRandom(seed: 42)
        XCTAssertEqual(a.next(32), -1170105035)
        XCTAssertEqual(a.next(32), 234785527)
        var b = JavaRandom(seed: 0)
        XCTAssertEqual(b.next(32), -1155484576)
        XCTAssertEqual(b.next(32), -723955400)
    }

    func testGridWithColumnsRespectsColumnLimitAndFillsCanvas() {
        for (n, c) in [(5, 2), (7, 3), (9, 3), (4, 6)] {
            let g = LayoutGenerator.gridWithColumns(n, c)
            assertTiles(g, n)
            var perRow: [Int: Int] = [:]
            for cell in g.cells { perRow[Int((cell.t * 1000).rounded()), default: 0] += 1 }
            XCTAssertLessThanOrEqual(perRow.values.max() ?? 0, min(c, n), "no row holds more than \(c) photos")
        }
    }

    func testSpacingAndMarginAreExactInPixels() {
        let l = LayoutGenerator.rows(2, 1) // two cells side by side
        let r = LayoutEngine.cellRects(l, canvasW: 1000, canvasH: 500, margin: 10, spacing: 20)
        XCTAssertEqual(r[0], FRect(10, 10, 490, 490))
        XCTAssertEqual(r[1], FRect(510, 10, 990, 490))
    }

    func testCellsNeverOverlapOrCollapseWithLargeSpacing() {
        for l in LayoutGenerator.candidates(7) {
            let r = LayoutEngine.cellRects(l, canvasW: 400, canvasH: 400, margin: 20, spacing: 300)
            for c in r { XCTAssertGreaterThanOrEqual(c.w, 1 - 1e-9); XCTAssertGreaterThanOrEqual(c.h, 1 - 1e-9) }
        }
    }

    func testAutoPicksSideBySideForTwoPortraitsAndStackedForTwoLandscapes() {
        XCTAssertEqual(LayoutGenerator.auto(photoAspects: [0.75, 0.75]).0.id, "rows-2-1")
        XCTAssertEqual(LayoutGenerator.auto(photoAspects: [1.5, 1.5]).0.id, "rows-2-2")
    }

    func testCropCostIsZeroWhenAspectsMatch() {
        let single = LayoutTemplate(id: "s", name: "s", cells: [.unit])
        XCTAssertEqual(LayoutGenerator.cropCost(single, canvasAspect: 1.5, photoAspects: [1.5]), 0, accuracy: 1e-9)
    }

    func testCanvasSizeForLongSideKeepsRatio() {
        XCTAssertTrue(LayoutEngine.sizeForLongSide(.portrait4x5, longSide: 2048) == (1638, 2048))
        XCTAssertTrue(LayoutEngine.sizeForLongSide(.wide16x9, longSide: 2048) == (2048, 1152))
        XCTAssertTrue(LayoutEngine.sizeForLongSide(.square, longSide: 1000) == (1000, 1000))
    }
}
