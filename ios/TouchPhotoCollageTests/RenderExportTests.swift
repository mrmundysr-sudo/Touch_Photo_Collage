import XCTest
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
@testable import TouchPhotoCollage

final class RenderExportTests: XCTestCase {
    private func render(_ env: TestSupport.Env, _ p: CollageProject, _ w: Int, _ h: Int, keepTransparent: Bool = false) -> CGImage {
        env.renderer.render(p, width: w, height: h, options: .init(keepTransparent: keepTransparent))!
    }

    private func sha(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: import

    func testImportCopiesWithoutTouchingTheOriginal() throws {
        let env = TestSupport.env()
        let src = TestSupport.halvesJPEG(env.root.appendingPathComponent("orig.jpg"), w: 40, h: 20, exif: 6)
        let before = try sha(src)
        let ref = try env.importer.importFile(at: src)
        XCTAssertEqual(try sha(src), before, "original untouched")
        XCTAssertEqual(ref.width, 40); XCTAssertEqual(ref.height, 20); XCTAssertEqual(ref.exif, 6)
        XCTAssertEqual(try sha(env.store.mediaDir.appendingPathComponent(ref.file)), before, "private copy is byte-identical")
    }

    func testImportRejectsNonImagesAndLeavesNoDebris() throws {
        let env = TestSupport.env()
        let txt = env.root.appendingPathComponent("note.txt")
        try Data("hello".utf8).write(to: txt)
        XCTAssertThrowsError(try env.importer.importFile(at: txt))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: env.store.mediaDir.path), [])
    }

    // MARK: orientation end to end

    func testExifOrientationIsAppliedWhenRendering() throws {
        let env = TestSupport.env()
        // raw 40x20: red left, blue right; EXIF 6 = rotate 90° clockwise, so red ends up on top
        let ref = try TestSupport.importPhoto(env, exif: 6)
        let img = render(env, TestSupport.flatProject(ref), 100, 100)
        XCTAssertTrue(TestSupport.isRed(TestSupport.pixel(img, 50, 25)), "top is red")
        XCTAssertTrue(TestSupport.isBlue(TestSupport.pixel(img, 50, 75)), "bottom is blue")
    }

    func testExifOrientationOneKeepsLeftRightAndUserRotationMirrorWork() throws {
        let env = TestSupport.env()
        let ref = try TestSupport.importPhoto(env)
        let plain = render(env, TestSupport.flatProject(ref), 100, 100)
        XCTAssertTrue(TestSupport.isRed(TestSupport.pixel(plain, 10, 50)))
        XCTAssertTrue(TestSupport.isBlue(TestSupport.pixel(plain, 90, 50)))
        let mirrored = render(env, TestSupport.flatProject(ref, mirror: true), 100, 100)
        XCTAssertTrue(TestSupport.isBlue(TestSupport.pixel(mirrored, 10, 50)))
        XCTAssertTrue(TestSupport.isRed(TestSupport.pixel(mirrored, 90, 50)))
        let rotated = render(env, TestSupport.flatProject(ref, rotation: 1), 100, 100) // clockwise: red on top
        XCTAssertTrue(TestSupport.isRed(TestSupport.pixel(rotated, 50, 10)))
        XCTAssertTrue(TestSupport.isBlue(TestSupport.pixel(rotated, 50, 90)))
    }

    func testFitModeKeepsWholePhotoUndistortedWithBars() throws {
        let env = TestSupport.env()
        let ref = try TestSupport.importPhoto(env) // 40x20, 2:1
        let img = render(env, TestSupport.flatProject(ref, fit: true), 100, 100)
        // whole photo is 100 x 50, centred: white bars above and below
        let bar = TestSupport.pixel(img, 50, 10)
        XCTAssertTrue(bar.r > 240 && bar.g > 240 && bar.b > 240, "bar is the white background")
        XCTAssertTrue(TestSupport.isRed(TestSupport.pixel(img, 5, 50)), "photo reaches the left edge, so nothing is cropped")
        XCTAssertTrue(TestSupport.isBlue(TestSupport.pixel(img, 95, 50)))
    }

    // MARK: export

    func testExportSizingRespectsMemoryBudgetAndRatios() {
        XCTAssertTrue(ExportSizing.size(.portrait4x5, quality: .standard, budgetBytes: .max) == (1638, 2048))
        XCTAssertTrue(ExportSizing.size(.portrait4x5, quality: .maximum, budgetBytes: .max) == (3840, 4800))
        XCTAssertTrue(ExportSizing.size(.wide16x9, quality: .standard, budgetBytes: .max) == (2048, 1152))
        let budget: Int64 = 24 * 1024 * 1024
        let (w, h) = ExportSizing.size(.square, quality: .maximum, budgetBytes: budget)
        XCTAssertLessThanOrEqual(Int64(w) * Int64(h) * 4, budget)
        XCTAssertGreaterThanOrEqual(max(w, h), 1024)
        XCTAssertGreaterThanOrEqual(ExportSizing.budgetBytes(availableMemory: 1), 24 * 1024 * 1024)
    }

    func testExportedDimensionsAndFormats() throws {
        let env = TestSupport.env()
        let ref = try TestSupport.importPhoto(env)
        var p = TestSupport.flatProject(ref, canvas: .portrait4x5)
        p.style.margin = 0
        let exporter = Exporter(mediaDir: env.store.mediaDir)
        let jpg = env.root.appendingPathComponent("out.jpg")
        let r = try exporter.export(p, ExportRequest(format: .jpeg, quality: .standard), to: jpg)
        XCTAssertEqual(r.width, 1638); XCTAssertEqual(r.height, 2048)
        XCTAssertGreaterThan(r.bytes, 0)
        let head = try Data(contentsOf: jpg).prefix(3)
        XCTAssertEqual(Array(head), [0xFF, 0xD8, 0xFF], "JPEG signature")
        let info = ImageIOUtil.info(at: jpg)
        XCTAssertEqual(info?.width, 1638); XCTAssertEqual(info?.height, 2048)
    }

    func testExportToFileWritesDecodablePngWithTransparency() throws {
        let env = TestSupport.env()
        let ref = try TestSupport.importPhoto(env)
        var p = TestSupport.flatProject(ref)
        p.style.margin = 0.25
        p.background.type = .transparent
        let png = env.root.appendingPathComponent("out.png")
        let r = try Exporter(mediaDir: env.store.mediaDir).export(p, ExportRequest(format: .png, quality: .standard, transparent: true), to: png)
        XCTAssertEqual(r.width, 2048)
        let src = CGImageSourceCreateWithURL(png as CFURL, nil)!
        XCTAssertEqual(CGImageSourceGetType(src) as String?, UTType.png.identifier)
        let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
        XCTAssertEqual(TestSupport.pixel(img, 5, 5).a, 0, "margin is see-through")
        XCTAssertEqual(TestSupport.pixel(img, 1024, 1024).a, 255, "photo is opaque")
    }

    func testTransparentBackgroundRendersWhiteWhenNotKept() throws {
        let env = TestSupport.env()
        let ref = try TestSupport.importPhoto(env)
        var p = TestSupport.flatProject(ref)
        p.style.margin = 0.25
        p.background.type = .transparent
        let white = render(env, p, 100, 100, keepTransparent: false)
        let px = TestSupport.pixel(white, 3, 3)
        XCTAssertTrue(px.r > 250 && px.g > 250 && px.b > 250 && px.a == 255)
        let clear = render(env, p, 100, 100, keepTransparent: true)
        XCTAssertEqual(TestSupport.pixel(clear, 3, 3).a, 0)
    }

    func testSourcePhotosAreUnchangedAfterEditingAndExporting() throws {
        let env = TestSupport.env()
        let ref = try TestSupport.importPhoto(env)
        let file = env.store.mediaDir.appendingPathComponent(ref.file)
        let before = try sha(file)
        var p = TestSupport.flatProject(ref)
        p.cells[0].filter = .sepia; p.cells[0].adjustments.sharpness = 1; p.cells[0].zoom = 2
        _ = try Exporter(mediaDir: env.store.mediaDir).export(p, ExportRequest(), to: env.root.appendingPathComponent("o.jpg"))
        XCTAssertEqual(try sha(file), before)
    }

    func testExportFileNamesAreSafe() {
        var p = TestSupport.flatProject(PhotoRef(id: "x", file: "x", width: 1, height: 1))
        p.name = "A/B: c"
        let n = Exporter.fileName(p, ExportRequest())
        XCTAssertTrue(n.hasPrefix("A_B_c_"), n)
        XCTAssertTrue(n.hasSuffix(".jpg"))
        p.name = "???"
        XCTAssertTrue(Exporter.fileName(p, ExportRequest(format: .png)).hasPrefix("collage_"))
    }

    // MARK: composition

    func testMultiPhotoCollageHasSpacingBackgroundAndRoundedCorners() throws {
        let env = TestSupport.env()
        let red = try TestSupport.importPhoto(env, w: 40, h: 40, left: .red, right: .red)
        let blue = try TestSupport.importPhoto(env, w: 40, h: 40, left: .blue, right: .blue)
        var p = ProjectOps.create(photos: [red, blue], mode: .collage, now: 1)
        p = ProjectOps.withLayout(p, LayoutGenerator.rows(2, 1), canvas: .square)
        p.style = CollageStyle(spacing: 0.1, margin: 0.1, cornerRadius: 0.1)
        p.background = CanvasBackground(type: .solid, color1: 0xFF00FF00)
        p = ProjectOps.autoCrop(p)
        let img = render(env, p, 200, 200)
        XCTAssertTrue(TestSupport.isRed(TestSupport.pixel(img, 50, 100)), "left cell")
        XCTAssertTrue(TestSupport.isBlue(TestSupport.pixel(img, 150, 100)), "right cell")
        let gap = TestSupport.pixel(img, 100, 100)
        XCTAssertTrue(gap.g > 200 && gap.r < 60 && gap.b < 60, "background shows in the gap")
        let margin = TestSupport.pixel(img, 4, 100)
        XCTAssertTrue(margin.g > 200 && margin.r < 60, "margin shows the background")
        let corner = TestSupport.pixel(img, 22, 22) // just inside the first cell's rounded corner
        XCTAssertTrue(corner.g > 150, "rounded corner reveals the background")
    }

    func testTextOverlayAndCaptionDrawPixels() throws {
        let env = TestSupport.env()
        let ref = try TestSupport.importPhoto(env, w: 40, h: 40, left: .red, right: .red)
        var p = TestSupport.flatProject(ref)
        let base = render(env, p, 200, 200)
        p.texts = [TextOverlay(id: "t", text: "WWWW", x: 0.5, y: 0.5, size: 0.3, color: 0xFFFFFFFF, font: .sans, bold: true, shadow: false)]
        let withText = render(env, p, 200, 200)
        var whiteish = 0
        let px = TestSupport.pixels(withText)
        for i in stride(from: 0, to: px.count, by: 4) where px[i] > 200 && px[i + 1] > 200 && px[i + 2] > 200 { whiteish += 1 }
        XCTAssertGreaterThan(whiteish, 100, "text pixels are drawn")
        _ = base

        p.texts = []
        let plain = render(env, p, 200, 200)
        p.cells[0].caption = CellCaption(name: "Anna", relation: "", age: "")
        let captioned = render(env, p, 200, 200)
        let a = TestSupport.pixel(plain, 10, 194), b = TestSupport.pixel(captioned, 10, 194)
        XCTAssertGreaterThan((a.r + a.g + a.b) - (b.r + b.g + b.b), 40, "caption scrim darkens the bottom edge")
    }

    func testTextBoundsContainTheTextCentre() {
        let env = TestSupport.env()
        var p = TestSupport.flatProject(PhotoRef(id: "x", file: "x", width: 10, height: 10))
        p.texts = [TextOverlay(id: "t", text: "Hello", x: 0.3, y: 0.7, size: 0.1), TextOverlay(id: "u", text: "  ", x: 0.5, y: 0.5)]
        let b = env.renderer.textBounds(p, width: 300, height: 300)
        XCTAssertTrue(b[0].contains(CGPoint(x: 90, y: 210)))
        XCTAssertTrue(b[1].isEmpty, "blank text has no hit box")
    }

    func testSharpnessAndFiltersChangePixelsButNotSize() throws {
        let env = TestSupport.env()
        let ref = try TestSupport.importPhoto(env, w: 40, h: 40)
        var p = TestSupport.flatProject(ref)
        let base = render(env, p, 120, 120)
        p.cells[0].filter = .blackWhite
        let bw = render(env, p, 120, 120)
        XCTAssertEqual(bw.width, base.width)
        let c = TestSupport.pixel(bw, 20, 60)
        XCTAssertLessThan(abs(c.r - c.g), 6, "black & white is grey")
        XCTAssertLessThan(abs(c.g - c.b), 6)
        XCTAssertTrue(TestSupport.isRed(TestSupport.pixel(base, 20, 60)), "unfiltered stays red")
        p.cells[0].filter = .none
        p.cells[0].adjustments.sharpness = 1
        let sharp = render(env, p, 120, 120)
        XCTAssertNotEqual(TestSupport.pixels(sharp), TestSupport.pixels(base), "sharpening alters the edge between red and blue")
    }

    func testEmptyCellsRenderWithoutCrashing() {
        let env = TestSupport.env()
        let p = CollageProject(
            id: "e", canvas: .square, layout: LayoutGenerator.rows(2, 1), cells: [CellEdit(), CellEdit()]
        )
        let img = env.renderer.render(p, width: 80, height: 80, options: .init(keepTransparent: true, showPlaceholders: true))
        XCTAssertNotNil(img)
    }

    func testMissingMediaFileRendersPlaceholderInsteadOfCrashing() {
        let env = TestSupport.env()
        let p = TestSupport.flatProject(PhotoRef(id: "gone", file: "gone.img", width: 40, height: 20))
        let img = render(env, p, 100, 100)
        let px = TestSupport.pixel(img, 50, 50)
        XCTAssertTrue(abs(px.r - 0x7A) < 4 && abs(px.g - 0x7A) < 4 && abs(px.b - 0x7A) < 4, "grey placeholder, got \(px)")
    }

    func testBackgroundsAndTexturesRenderForEveryKind() {
        let env = TestSupport.env()
        let layout = LayoutTemplate(id: "s", name: "s", cells: [.unit])
        for kind in TextureKind.allCases {
            var p = CollageProject(id: "b", canvas: .square, layout: layout, cells: [CellEdit()])
            p.background = CanvasBackground(type: .texture, color1: 0xFFFFFFFF, color2: 0xFF8A7A5A, texture: kind)
            XCTAssertNotNil(env.renderer.render(p, width: 120, height: 120), "\(kind)")
        }
        var g = CollageProject(id: "g", canvas: .square, layout: layout, cells: [CellEdit()])
        g.background = CanvasBackground(type: .gradient, color1: 0xFFFF0000, color2: 0xFF0000FF, angle: 0)
        let img = env.renderer.render(g, width: 100, height: 100)!
        let l = TestSupport.pixel(img, 2, 50), r = TestSupport.pixel(img, 97, 50)
        XCTAssertTrue(l.r > r.r && r.b > l.b, "gradient runs from red to blue")
    }

    // MARK: live layer

    func testLiveDrawMatchesFullRenderForTheSameCropAndLeavesOtherCellsUntouched() throws {
        let env = TestSupport.env()
        let a = try TestSupport.importPhoto(env, w: 60, h: 40)
        let b = try TestSupport.importPhoto(env, w: 40, h: 60, left: .green, right: .yellow)
        var p = ProjectOps.create(photos: [a, b], mode: .collage, now: 1)
        p = ProjectOps.withLayout(p, LayoutGenerator.rows(2, 1), canvas: .square)
        p.cells[0].zoom = 2; p.cells[0].cx = 0.4; p.cells[0].cy = 0.5; p.cells[0].manual = true
        let full = render(env, p, 200, 200)
        guard let ctx = CG.makeContext(width: 200, height: 200, alpha: true) else { return XCTFail("context") }
        let raw = env.provider.image(for: a, sample: 1)!
        env.renderer.drawCellLive(ctx, project: p, index: 0, cell: p.cells[0], image: raw, width: 200, height: 200)
        let live = ctx.makeImage()!
        let rect = CollageRenderer.cellRects(p, width: 200, height: 200)[0]
        let fp = TestSupport.pixels(full), lp = TestSupport.pixels(live)
        var maxDiff = 0
        for y in Int(rect.t) + 3..<Int(rect.b) - 3 { for x in Int(rect.l) + 3..<Int(rect.r) - 3 {
            let i = (y * 200 + x) * 4
            maxDiff = max(maxDiff, abs(Int(fp[i]) - Int(lp[i])), abs(Int(fp[i + 1]) - Int(lp[i + 1])), abs(Int(fp[i + 2]) - Int(lp[i + 2])))
        } }
        XCTAssertLessThanOrEqual(maxDiff, 3, "live frame equals the final render")
        XCTAssertEqual(TestSupport.pixel(live, 150, 100).a, 0, "other cells are not painted")
        // a different live crop changes the picture
        var moved = p.cells[0]; moved.zoom = 4; moved.cx = 0.8
        guard let ctx2 = CG.makeContext(width: 200, height: 200, alpha: true) else { return XCTFail("context") }
        env.renderer.drawCellLive(ctx2, project: p, index: 0, cell: moved, image: raw, width: 200, height: 200)
        XCTAssertNotEqual(TestSupport.pixels(ctx2.makeImage()!), lp)
    }
}
