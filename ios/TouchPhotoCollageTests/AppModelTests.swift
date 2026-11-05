import XCTest
@testable import TouchPhotoCollage

/// End-to-end tests of the app model (the port of the Android view model): import, editing, undo/redo, autosave, reopen,
/// templates and the live-gesture commit path, all against a private temporary storage folder.
@MainActor
final class AppModelTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        super.setUp()
        root = TestSupport.tempDir("model")
    }

    private func makeModel() -> AppModel { AppModel(root: root) }

    private func open(_ model: AppModel, _ mode: ProjectMode = .collage, count: Int = 4) async {
        model.startNew(mode, urls: TestPhotos.make(count: count))
        let ok = await waitUntil(timeout: 20) { model.screen == .editor && model.project != nil }
        XCTAssertTrue(ok, "editor opened")
    }

    func testStartNewImportsPhotosAndOpensTheEditor() async {
        let m = makeModel()
        await open(m)
        XCTAssertEqual(m.project?.photoCount, 4)
        XCTAssertEqual(m.project?.mode, .collage)
        XCTAssertFalse(m.canUndo)
        // every photo is a private copy inside the app's storage
        for c in m.project!.cells {
            let f = m.store.mediaDir.appendingPathComponent(c.photo!.file)
            XCTAssertTrue(FileManager.default.fileExists(atPath: f.path))
        }
    }

    func testTooFewPhotosForCompareShowsAMessageAndStaysHome() async {
        let m = makeModel()
        m.startNew(.compare, urls: TestPhotos.make(count: 1))
        let shown = await waitUntil { m.toast != nil }
        XCTAssertTrue(shown)
        XCTAssertEqual(m.screen, .home)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: m.store.mediaDir.path), [], "no orphaned photo copies")
    }

    func testUnreadableFilesAreSkippedWithAMessage() async {
        let m = makeModel()
        let bad = IncomingFiles.directory.appendingPathComponent("bad-\(UUID().uuidString).jpg")
        try? Data("not an image".utf8).write(to: bad)
        var urls = TestPhotos.make(count: 2)
        urls.append(bad)
        m.startNew(.collage, urls: urls)
        _ = await waitUntil(timeout: 20) { m.screen == .editor }
        XCTAssertEqual(m.project?.photoCount, 2)
        XCTAssertNotNil(m.toast)
    }

    func testUndoRedoAndLiveEditsAreOneStep() async {
        let m = makeModel()
        await open(m)
        let original = m.project!
        m.setStyle { $0.spacing = 0.03 }
        m.setStyle { $0.spacing = 0.05 }
        m.setStyle { $0.spacing = 0.07 }
        m.endLive()
        XCTAssertEqual(m.project?.style.spacing, 0.07)
        m.undo()
        XCTAssertEqual(m.project?.style.spacing, original.style.spacing, "a whole slider drag is a single undo step")
        XCTAssertTrue(m.canRedo)
        m.redo()
        XCTAssertEqual(m.project?.style.spacing, 0.07)
        m.setCanvas(.story9x16)
        XCTAssertEqual(m.project?.canvas, .story9x16)
        m.undo()
        XCTAssertEqual(m.project?.canvas, original.canvas)
    }

    func testCommitCropIsManualAndUndoable() async {
        let m = makeModel()
        await open(m)
        let before = m.project!.cells[0]
        m.commitCrop(0, zoom: 2.5, cx: 0.4, cy: 0.6)
        let c = m.project!.cells[0]
        XCTAssertEqual(c.zoom, 2.5); XCTAssertEqual(c.cx, 0.4); XCTAssertEqual(c.cy, 0.6); XCTAssertTrue(c.manual)
        m.undo()
        XCTAssertEqual(m.project!.cells[0].zoom, before.zoom)
        XCTAssertFalse(m.project!.cells[0].manual)
    }

    func testManualCropSurvivesLayoutChangesAndResetRestoresAutomaticPosition() async {
        let m = makeModel()
        await open(m)
        m.commitCrop(1, zoom: 3, cx: 0.3, cy: 0.3)
        m.setStyle(live: false) { $0.margin = 0.04 }
        XCTAssertEqual(m.project!.cells[1].zoom, 3, "automatic re-positioning never touches a manual cell")
        m.resetCell(1)
        XCTAssertFalse(m.project!.cells[1].manual)
        XCTAssertEqual(m.project!.cells[1].zoom, 1)
    }

    func testStepCellMovesAndZoomsForAccessibilityActions() async {
        let m = makeModel()
        await open(m)
        m.setViewport(CGSize(width: 390, height: 500), scale: 3)
        m.selectCell(0)
        m.stepCell(0, panFracX: 0, panFracY: 0, zoomFactor: 1.25)
        XCTAssertEqual(m.project!.cells[0].zoom, 1.25, accuracy: 1e-9)
        XCTAssertTrue(m.project!.cells[0].manual)
    }

    func testSwapMoveRemoveAndSelection() async {
        let m = makeModel()
        await open(m)
        let ids = m.project!.cells.map { $0.photo!.id }
        m.swapCells(0, 3)
        XCTAssertEqual(m.project!.cells[0].photo!.id, ids[3])
        XCTAssertEqual(m.selection.cell, 3)
        m.moveCell(3, delta: -1)
        XCTAssertEqual(m.selection.cell, 2)
        m.removeCell(0)
        XCTAssertEqual(m.project!.photoCount, 3)
        XCTAssertNil(m.selection.cell)
    }

    func testPerCellAdjustmentsAndTextEdits() async {
        let m = makeModel()
        await open(m)
        m.editCell(2) { $0.filter = .sepia }
        XCTAssertEqual(m.project!.cells[2].filter, .sepia)
        XCTAssertEqual(m.project!.cells[1].filter, FilterType.none)
        m.editAllCells { $0.adjustments.brightness = 0.3 }
        XCTAssertTrue(m.project!.cells.allSatisfy { $0.adjustments.brightness == 0.3 })
        m.addText("Hello")
        XCTAssertEqual(m.project!.texts.count, 1)
        XCTAssertEqual(m.selection.text, 0)
        m.moveText(0, nx: 1.5, ny: -3)
        XCTAssertEqual(m.project!.texts[0].x, 0.98, "text stays on the canvas")
        XCTAssertEqual(m.project!.texts[0].y, 0.02)
        m.deleteText(0)
        XCTAssertTrue(m.project!.texts.isEmpty)
    }

    func testRotateMirrorFitAndAvoidCropping() async {
        let m = makeModel()
        await open(m)
        m.rotateCell(0)
        XCTAssertEqual(m.project!.cells[0].rotation, 1)
        m.mirrorCell(0)
        XCTAssertTrue(m.project!.cells[0].mirror)
        m.toggleFit(0)
        XCTAssertTrue(m.project!.cells[0].fit)
        m.setAvoidCropping(true)
        XCTAssertTrue(m.project!.cells.allSatisfy { $0.fit })
        m.setAvoidCropping(false)
        XCTAssertTrue(m.project!.cells.allSatisfy { !$0.fit })
    }

    func testPreviewFrameIsRenderedAtTheCanvasPixelSize() async {
        let m = makeModel()
        await open(m)
        m.setViewport(CGSize(width: 300, height: 400), scale: 2)
        let ok = await waitUntil(timeout: 20) { m.preview != nil && m.preview!.image.width == m.canvasPixels.w }
        XCTAssertTrue(ok, "preview rendered")
        XCTAssertGreaterThan(m.canvasSize.width, 0)
        XCTAssertLessThanOrEqual(m.canvasSize.width, 300 + 0.5)
        XCTAssertLessThanOrEqual(m.canvasSize.height, 400 + 0.5)
        let aspect = Double(m.canvasPixels.w) / Double(m.canvasPixels.h)
        XCTAssertEqual(aspect, m.project!.canvas.aspect, accuracy: 0.01)
    }

    func testProjectIsSavedAndReopensAfterRestart() async {
        let m = makeModel()
        await open(m)
        m.rename("Summer trip")
        m.commitCrop(0, zoom: 2, cx: 0.45, cy: 0.5)
        let expected = m.project!
        m.closeEditor()
        _ = await waitUntil(timeout: 20) { m.screen == .home && m.home.recents.count == 1 }
        XCTAssertEqual(m.home.recents.first?.name, "Summer trip")
        XCTAssertNotNil(m.home.recents.first?.thumb, "a thumbnail is stored for the home screen")

        let again = makeModel()
        _ = await waitUntil { again.home.recents.count == 1 }
        again.openSaved(m.home.recents[0].id)
        _ = await waitUntil(timeout: 20) { again.screen == .editor }
        var got = again.project!
        got.updatedAt = expected.updatedAt
        XCTAssertEqual(got.cells.map { $0.photo?.id }, expected.cells.map { $0.photo?.id })
        XCTAssertEqual(got.cells[0].zoom, 2); XCTAssertEqual(got.cells[0].cx, 0.45)
        XCTAssertEqual(got.name, "Summer trip")
    }

    func testFlushPendingSavePersistsImmediatelyWhenTheAppLeavesTheForeground() async {
        let m = makeModel()
        await open(m)
        m.rename("Flushed")
        m.flushPendingSave()
        let reloaded = m.store.load(m.project!.id)
        XCTAssertEqual(reloaded?.name, "Flushed")
    }

    func testDeletingAProjectRemovesItAndItsPhotos() async {
        let m = makeModel()
        await open(m, count: 2)
        let id = m.project!.id
        m.closeEditor()
        _ = await waitUntil(timeout: 20) { m.home.recents.count == 1 }
        m.deleteProject(id)
        _ = await waitUntil { m.home.recents.isEmpty }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: m.store.mediaDir.path), [])
    }

    func testTemplatesCanBeSavedAndUsedForNewProjects() async {
        let m = makeModel()
        await open(m, count: 3)
        m.setStyle(live: false) { $0.cornerRadius = 0.12 }
        m.saveTemplate("My look")
        _ = await waitUntil { m.home.templates.count == 1 }
        let t = m.home.templates[0]
        XCTAssertEqual(t.name, "My look")
        XCTAssertEqual(t.style.cornerRadius, 0.12)
        m.closeEditor()
        _ = await waitUntil { m.screen == .home }
        m.startFromTemplate(t, urls: TestPhotos.make(count: 2))
        _ = await waitUntil(timeout: 20) { m.screen == .editor }
        XCTAssertEqual(m.project?.layout.count, 3)
        XCTAssertEqual(m.project?.photoCount, 2, "extra template cells stay empty")
        XCTAssertEqual(m.project?.style.cornerRadius, 0.12)
        m.deleteTemplate(t.id)
        _ = await waitUntil { m.home.templates.isEmpty }
    }

    func testAddAndReplacePhotos() async {
        let m = makeModel()
        await open(m, count: 2)
        m.addPhotos(TestPhotos.make(count: 2))
        _ = await waitUntil(timeout: 20) { m.project?.photoCount == 4 }
        XCTAssertEqual(m.project?.photoCount, 4)
        let oldId = m.project!.cells[1].photo!.id
        m.replacePhoto(1, url: TestPhotos.make(count: 1)[0])
        _ = await waitUntil(timeout: 20) { m.project?.cells[1].photo?.id != oldId }
        XCTAssertNotEqual(m.project?.cells[1].photo?.id, oldId)
    }

    func testExportToPhotosFileAndShareFile() async throws {
        let m = makeModel()
        await open(m, count: 2)
        let (w, h) = m.sizeFor(.standard)
        XCTAssertEqual(max(w, h), 2048)
        m.export(ExportRequest(format: .jpeg, quality: .standard), share: true)
        let shared = await waitUntil(timeout: 30) { m.shareItem != nil }
        XCTAssertTrue(shared)
        let url = try XCTUnwrap(m.shareItem?.url)
        XCTAssertEqual(url.pathExtension, "jpg")
        XCTAssertEqual(ImageIOUtil.info(at: url)?.width, w)
        XCTAssertNil(m.busy)
    }

    func testFaceDetectionRunsAndNeverBlocksOrCrashesOnPhotosWithoutFaces() async {
        let m = makeModel()
        await open(m, count: 3)
        let done = await waitUntil(timeout: 30) { m.facesPending == 0 && m.project!.cells.allSatisfy { $0.photo?.faces != nil } }
        XCTAssertTrue(done, "every photo was analysed (no faces in synthetic photos) and fell back to centre cropping")
        XCTAssertTrue(m.project!.cells.allSatisfy { $0.zoom == 1 })
    }

    func testThemeAndGesturePreferencesPersist() {
        let m = makeModel()
        // restore defaults afterwards so other tests (and the UI tests on the same simulator) start clean
        defer { m.setTheme(.system); m.setTouchMode(.pan); m.setPinchEnabled(true); m.setZoomSensitivity(1) }
        m.setTheme(.dark); m.setTouchMode(.zoom); m.setPinchEnabled(false); m.setZoomSensitivity(2)
        let again = makeModel()
        XCTAssertEqual(again.theme, .dark); XCTAssertEqual(again.touchMode, .zoom)
        XCTAssertFalse(again.pinchEnabled); XCTAssertEqual(again.zoomSensitivity, 2)
    }

    func testFitInside() {
        XCTAssertTrue(AppModel.fitInside(availW: 300, availH: 400, aspect: 1) == (300, 300))
        XCTAssertTrue(AppModel.fitInside(availW: 300, availH: 200, aspect: 1) == (200, 200))
        XCTAssertTrue(AppModel.fitInside(availW: 300, availH: 400, aspect: 0.5) == (200, 400))
    }
}
