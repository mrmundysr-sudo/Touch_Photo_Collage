import XCTest
@testable import TouchPhotoCollage

final class ProjectTests: XCTestCase {
    private func photos(_ n: Int) -> [PhotoRef] {
        (0..<n).map { PhotoRef(id: "p\($0)", file: "p\($0).img", width: 1200 + $0 * 100, height: 800, exif: ($0 % 8) + 1, faces: $0 == 0 ? [FRect(0.3, 0.2, 0.5, 0.45)] : nil) }
    }

    private func rich() -> CollageProject {
        var p = ProjectOps.create(photos: photos(4), mode: .family, now: 1234, name: "Rich ☺ project")
        p.cells[1].adjustments = Adjustments(brightness: 0.2, contrast: -0.3, saturation: 0.4, warmth: 0.1, sharpness: 0.5)
        p.cells[1].filter = .vintage
        p.cells[2].caption = CellCaption(name: "Anna", relation: "Mother", age: "34")
        p.cells[2].rotation = 3; p.cells[2].mirror = true; p.cells[2].fit = true; p.cells[2].manual = true
        p.cells[2].zoom = 2.25; p.cells[2].cx = 0.31; p.cells[2].cy = 0.62
        p.texts = [TextOverlay(id: "t1", text: "Hello\nWorld", x: 0.3, y: 0.7, size: 0.1, color: 0xFF112233, font: .script, bold: true, italic: true, align: .right, shadow: false, backgroundColor: 0x99000000, rotation: -12)]
        p.background = CanvasBackground(type: .gradient, color1: 0xFF123456, color2: 0xFFABCDEF, texture: .linen, angle: 45)
        p.style = CollageStyle(spacing: 0.02, margin: 0.03, cornerRadius: 0.1, borderWidth: 0.01, borderColor: 0xFFFF0000)
        return p
    }

    func testRoundTripPreservesEverything() throws {
        let p = rich()
        let back = try ProjectJson.parseProject(try ProjectJson.serialize(p))
        XCTAssertEqual(back, p)
    }

    func testJsonUsesTheSameKeysAsTheAndroidApp() throws {
        let d = ProjectJson.toDict(rich())
        for k in ["version", "id", "name", "createdAt", "updatedAt", "mode", "canvas", "layout", "style", "background", "cells", "texts", "faceMode"] {
            XCTAssertNotNil(d[k], k)
        }
        let text = (d["texts"] as? [[String: Any]])?.first
        XCTAssertEqual(text?["color"] as? Int, Int(Int32(bitPattern: 0xFF112233)), "colours are stored as signed 32-bit ints like Android")
    }

    func testOlderOrPartialFilesStillOpenWithDefaults() throws {
        let json = #"{"id":"x","layout":{"id":"l","cells":[[0,0,0.5,1],[0.5,0,1,1]]},"cells":[{"zoom":2}]}"#
        let p = try ProjectJson.parseProject(Data(json.utf8))
        XCTAssertEqual(p.name, "Untitled collage")
        XCTAssertEqual(p.cells.count, 2, "cells are padded to match the layout")
        XCTAssertEqual(p.cells[0].zoom, 2)
        XCTAssertNil(p.cells[1].photo)
        XCTAssertEqual(p.background.type, .solid)
        XCTAssertEqual(p.canvas, .square)
    }

    func testSaveAndReopenFromDisk() throws {
        let env = TestSupport.env()
        let p = rich()
        try env.store.save(p)
        XCTAssertEqual(env.store.load(p.id), p)
        XCTAssertNil(env.store.load("missing"))
    }

    func testCorruptFilesAreSkippedAndDoNotBreakTheList() throws {
        let env = TestSupport.env()
        try env.store.save(rich())
        try Data("{ not json".utf8).write(to: env.root.appendingPathComponent("projects/broken.json"))
        let list = env.store.list()
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].photoCount, 4)
    }

    func testListIsNewestFirst() throws {
        let env = TestSupport.env()
        var a = rich(); a.id = "a"; a.updatedAt = 100
        var b = rich(); b.id = "b"; b.updatedAt = 200
        try env.store.save(a); try env.store.save(b)
        XCTAssertEqual(env.store.list().map { $0.id }, ["b", "a"])
    }

    func testDeletingProjectRemovesUnreferencedMediaOnly() throws {
        let env = TestSupport.env()
        func proj(_ id: String, _ file: String) -> CollageProject {
            ProjectOps.create(photos: [PhotoRef(id: id, file: file, width: 10, height: 10)], mode: .collage, now: 1)
        }
        var a = proj("a", "a.img"); a.id = "A"
        var b = proj("b", "b.img"); b.id = "B"
        try env.store.save(a); try env.store.save(b)
        for f in ["a.img", "b.img", "orphan.img"] { try Data([1, 2, 3]).write(to: env.store.mediaDir.appendingPathComponent(f)) }
        env.store.delete("A")
        let left = Set((try FileManager.default.contentsOfDirectory(atPath: env.store.mediaDir.path)))
        XCTAssertEqual(left, ["b.img"])
    }

    func testTemplatesPersist() throws {
        let env = TestSupport.env()
        let ts = TemplateStore(root: env.root)
        let t = ProjectOps.toTemplate(rich(), name: "Mine")
        ts.add(t)
        XCTAssertEqual(TemplateStore(root: env.root).list(), [t])
        ts.delete(t.id)
        XCTAssertTrue(TemplateStore(root: env.root).list().isEmpty)
    }

    func testFaceModeOnlyOverwritesNonManualCells() {
        var p = ProjectOps.create(photos: [PhotoRef(id: "a", file: "a", width: 1200, height: 800), PhotoRef(id: "b", file: "b", width: 1200, height: 800)], mode: .collage, now: 1)
        p = ProjectOps.withLayout(p, LayoutGenerator.rows(2, 1), canvas: .square)
        p.cells[1].manual = true; p.cells[1].zoom = 2; p.cells[1].cx = 0.3; p.cells[1].cy = 0.6
        let q = ProjectOps.withFaces(p, photoId: "a", faces: [FRect(0.8, 0.3, 0.9, 0.5)])
        XCTAssertGreaterThan(q.cells[0].cx, 0.5, "automatic cell follows the face")
        XCTAssertEqual(q.cells[1].zoom, 2); XCTAssertEqual(q.cells[1].cx, 0.3); XCTAssertEqual(q.cells[1].cy, 0.6)
    }

    func testCreateModes() {
        let two = photos(2)
        let compare = ProjectOps.create(photos: two, mode: .compare, now: 1)
        XCTAssertEqual(compare.layout.count, 2)
        XCTAssertEqual(compare.style.margin, 0)
        let family = ProjectOps.create(photos: photos(3), mode: .family, now: 1)
        XCTAssertEqual(family.faceMode, .align)
        XCTAssertTrue(family.layout.id.hasPrefix("rows-") || family.layout.id.hasPrefix("cols-"))
        let grid = ProjectOps.create(photos: photos(7), mode: .grid, now: 1, gridColumns: 3)
        XCTAssertEqual(grid.layout.count, 7)
        XCTAssertEqual(grid.style.cornerRadius, 0)
    }

    func testSwapMoveRemoveAndPhotosEdits() {
        let p = ProjectOps.create(photos: photos(3), mode: .collage, now: 1)
        let s = ProjectOps.swapCells(p, 0, 2)
        XCTAssertEqual(s.cells[0].photo?.id, "p2"); XCTAssertEqual(s.cells[2].photo?.id, "p0")
        XCTAssertEqual(ProjectOps.swapCells(p, 0, 9), p, "out-of-range swap is ignored")
        let m = ProjectOps.moveCell(p, from: 0, to: 2)
        XCTAssertEqual(m.cells.map { $0.photo?.id }, ["p1", "p2", "p0"])
        let r = ProjectOps.removeCell(p, 1)
        XCTAssertEqual(r.cells.map { $0.photo?.id }, ["p0", "p2"])
        XCTAssertEqual(r.layout.count, 2)
        let more = ProjectOps.withPhotos(p, p.cells.compactMap { $0.photo } + [PhotoRef(id: "new", file: "n", width: 10, height: 10)])
        XCTAssertEqual(more.layout.count, 4)
    }

    func testFromTemplateLeavesExtraCellsEmpty() {
        let t = ProjectOps.toTemplate(ProjectOps.create(photos: photos(4), mode: .collage, now: 1), name: "T")
        let p = ProjectOps.fromTemplate(t, photos: Array(photos(2)), now: 5)
        XCTAssertEqual(p.cells.count, 4)
        XCTAssertEqual(p.photoCount, 2)
    }

    func testCaptionDisplay() {
        XCTAssertEqual(CellCaption(name: "Anna", relation: "Mother", age: "34").display(), "Anna · Mother · age 34")
        XCTAssertEqual(CellCaption(name: "", relation: "", age: "toddler").display(), "toddler")
        XCTAssertTrue(CellCaption().isBlank)
    }
}
