import XCTest

/// Drives the real app in the iOS simulator. Photos come from the app's built-in synthetic sample photos (launch
/// argument `-UITestSeed`), because the system photo picker runs out of process and cannot be scripted reliably.
final class TouchPhotoCollageUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    // MARK: helpers

    @discardableResult
    private func launch(reset: Bool = true, introSeen: Bool = true, extra: [String] = []) -> XCUIApplication {
        let a = XCUIApplication()
        var args = ["-UITestSeed"]
        if reset { args.append("-UITestReset") }
        if introSeen { args.append("-UITestIntroSeen") }
        a.launchArguments = args + extra + ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        a.launch()
        app = a
        return a
    }

    private func any(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private var canvas: XCUIElement { any("collageCanvas") }

    @discardableResult
    private func openEditor(tile: String = "createCollage") -> XCUIElement {
        let create = any(tile)
        XCTAssertTrue(create.waitForExistence(timeout: 15), "home shows \(tile)")
        create.tap()
        XCTAssertTrue(canvas.waitForExistence(timeout: 30), "editor canvas appears")
        return canvas
    }

    private func shot(_ name: String) {
        // XCUIScreen captures in the device's native (portrait) orientation; the app screenshot follows interface rotation.
        let s = XCUIDevice.shared.orientation.isLandscape ? app.screenshot() : XCUIScreen.main.screenshot()
        let att = XCTAttachment(screenshot: s)
        att.name = name
        att.lifetime = .keepAlways
        add(att)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let suffix = ProcessInfo.processInfo.environment["SCREENSHOT_SUFFIX"] ?? ""
            try? s.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name)\(suffix).png"))
        }
    }

    private func settle(_ seconds: TimeInterval = 0.8) { Thread.sleep(forTimeInterval: seconds) }

    /// (zoom, centreX, centreY) of the selected photo, read from the canvas' accessibility value.
    private func crop() -> (zoom: Double, cx: Double, cy: Double)? {
        guard let v = canvas.value as? String else { return nil }
        let nums = v.split(whereSeparator: { !"0123456789.".contains($0) }).compactMap { Double($0) }
        // "Photo 1 selected, zoom 2.0 times, centre 0.50 0.50" -> [1, 2.0, 0.50, 0.50]
        guard nums.count >= 4 else { return nil }
        return (nums[1], nums[2], nums[3])
    }

    private func drag(from a: CGVector, by d: CGVector, hold: TimeInterval = 0.1) {
        let start = canvas.coordinate(withNormalizedOffset: a)
        start.press(forDuration: hold, thenDragTo: start.withOffset(d))
    }

    // MARK: tests

    func testHomeShowsPrivacyNoteAndCreatesACollage() {
        launch()
        let title = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Photo Collage'")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 15), "home shows the app title")
        XCTAssertTrue(app.staticTexts["Recent projects"].exists)
        XCTAssertTrue(app.staticTexts["Saved templates"].exists)
        XCTAssertTrue(app.staticTexts["Your collages will appear here"].exists, "empty state is explained")
        settle(); shot("01-home-empty")
        openEditor()
        XCTAssertTrue(any("saveButton").exists)
        XCTAssertTrue(any("undoButton").exists)
        XCTAssertFalse(any("undoButton").isEnabled, "nothing to undo yet")
        XCTAssertTrue(any("modePan").exists && any("modeZoom").exists && any("resetPhoto").exists)
        XCTAssertTrue(app.staticTexts["Tap a photo to choose it"].exists)
        settle(1.5); shot("02-editor-no-selection")
    }

    func testOneFingerPanAndZoomWorkAndDoNotFightSelection() {
        launch()
        openEditor()
        settle(1)
        // every touch starts on the same point, so it always lands in the same photo
        let p = CGVector(dx: 0.25, dy: 0.3)

        // tapping selects a photo and commits nothing
        canvas.coordinate(withNormalizedOffset: p).tap()
        settle(0.5)
        guard let start = crop() else { return XCTFail("no selection value: \(String(describing: canvas.value))") }
        XCTAssertEqual(start.zoom, 1.0, accuracy: 0.05)
        XCTAssertFalse(any("undoButton").isEnabled, "a tap must not change the picture")
        XCTAssertTrue(app.staticTexts["PAN: drag one finger to move the photo"].exists, "the banner says what one finger does")

        // ZOOM mode: slide one finger up. 160 points would be exactly one doubling; 100 points is 2^(100/160) = 1.54
        any("modeZoom").tap()
        XCTAssertTrue(app.staticTexts["ZOOM: slide one finger up to zoom in, down to zoom out"].waitForExistence(timeout: 3))
        drag(from: p, by: CGVector(dx: 0, dy: -100))
        settle(0.8)
        guard let z1 = crop() else { return XCTFail("no crop after zoom") }
        XCTAssertGreaterThan(z1.zoom, 1.4, "sliding up zooms in (got \(z1.zoom))")
        XCTAssertLessThan(z1.zoom, 2.2, "zoom is proportional to travel, not a big step (got \(z1.zoom))")
        XCTAssertEqual(z1.cx, start.cx, accuracy: 0.03, "zoom mode never moves the photo sideways")
        XCTAssertTrue(any("undoButton").isEnabled, "the gesture committed as an undo step")
        shot("03-one-finger-zoomed")

        // sliding down zooms back out
        drag(from: p, by: CGVector(dx: 0, dy: 100))
        settle(0.8)
        let z2 = crop()?.zoom ?? 99
        XCTAssertLessThan(z2, z1.zoom - 0.2, "sliding down zooms out (\(z1.zoom) -> \(z2))")

        // zoom in again, then PAN: one finger drags the photo, zoom unchanged
        drag(from: p, by: CGVector(dx: 0, dy: -150))
        settle(0.5)
        any("modePan").tap()
        let before = crop()!
        XCTAssertGreaterThan(before.zoom, 1.5)
        drag(from: p, by: CGVector(dx: -50, dy: 0))
        settle(0.8)
        let after = crop()!
        XCTAssertEqual(after.zoom, before.zoom, accuracy: 0.02, "panning never changes zoom")
        XCTAssertGreaterThan(after.cx, before.cx + 0.01, "dragging left moves the photo left (the window moves right)")
        shot("04-one-finger-panned")

        // undo walks back, reset returns to the automatic placement
        any("undoButton").tap()
        settle(0.5)
        any("resetPhoto").tap()
        settle(0.5)
        XCTAssertEqual(crop()?.zoom ?? 99, 1.0, accuracy: 0.05, "reset restores the automatic placement")
    }

    func testSelectingAnotherPhotoNeverDisturbsCropsAndLongPressSwaps() {
        launch()
        openEditor()
        settle(1)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.25)).tap()
        settle(0.4)
        let c1 = crop()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.8)).tap()
        settle(0.4)
        let c2 = crop()
        XCTAssertNotNil(c1); XCTAssertNotNil(c2)
        XCTAssertFalse(any("undoButton").isEnabled, "selecting photos changes nothing")

        // long press one photo and drop it on another: swap
        let from = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.2))
        let to = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.8))
        from.press(forDuration: 1.0, thenDragTo: to)
        settle(1)
        XCTAssertTrue(any("undoButton").isEnabled, "swapping is an undoable edit")
        shot("05-after-swap")
        any("undoButton").tap()
        settle(0.5)
        XCTAssertFalse(any("undoButton").isEnabled)
    }

    func testEditingPanelsLayoutStyleAdjustTextFaces() {
        launch()
        openEditor()
        settle(1)
        shot("06-layout-panel")
        // a different layout
        XCTAssertTrue(any("shuffleArtistic").waitForExistence(timeout: 5))
        any("shuffleArtistic").tap()
        settle(0.8)
        XCTAssertTrue(any("undoButton").isEnabled)
        // canvas shape
        app.buttons["Portrait 4:5"].firstMatch.tap()
        settle(0.8)
        shot("07-portrait-canvas")

        any("tab-Style").tap()
        settle(0.5)
        XCTAssertTrue(app.staticTexts["Spacing"].waitForExistence(timeout: 3))
        let slider = app.sliders["Spacing"]
        if slider.exists { slider.adjust(toNormalizedSliderPosition: 0.7) }
        settle(0.5)
        shot("08-style-panel")

        any("tab-Adjust").tap()
        app.buttons["Black & white"].firstMatch.tap()
        settle(0.8)
        shot("09-adjust-black-and-white")

        any("tab-Text").tap()
        any("addText").tap()
        let field = any("overlayText")
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        settle(0.8)
        shot("10-text-added")

        any("tab-Faces").tap()
        XCTAssertTrue(app.staticTexts["Automatic positioning"].waitForExistence(timeout: 3))
        settle(0.5)
        shot("11-faces-panel")
    }

    func testSaveSheetShareSheetAndPermissionExplanation() {
        launch(extra: ["-UITestPhotosDenied"])
        openEditor()
        settle(1)
        any("saveButton").tap()
        let summary = any("exportSummary")
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains("2048"), summary.label)
        XCTAssertTrue(app.buttons["PNG · lossless"].firstMatch.exists)
        shot("12-save-sheet")

        // Photos access denied: a clear explanation with a way forward
        any("saveToPhotos").tap()
        let alert = app.alerts["Photos access is off"]
        XCTAssertTrue(alert.waitForExistence(timeout: 20), "denied state is explained")
        XCTAssertTrue(alert.buttons["Open Settings"].exists)
        XCTAssertTrue(alert.buttons["Share instead"].exists)
        shot("13-photos-denied")
        alert.buttons["Cancel"].tap()
    }

    func testShareSheetOpens() {
        launch()
        openEditor()
        settle(1)
        any("saveButton").tap()
        XCTAssertTrue(any("shareCollage").waitForExistence(timeout: 5))
        any("shareCollage").tap()
        let activity = app.descendants(matching: .any)["ActivityListView"].firstMatch
        XCTAssertTrue(activity.waitForExistence(timeout: 30), "the system share sheet opens")
        settle(1)
        shot("14-share-sheet")
    }

    func testSaveToPhotosShowsConfirmation() {
        launch()
        // the CI job pre-grants add-only photo access; on a dev machine the system prompt is accepted here
        addUIInterruptionMonitor(withDescription: "Photos permission") { alert in
            for label in ["Allow Full Access", "Allow", "OK"] where alert.buttons[label].exists { alert.buttons[label].tap(); return true }
            return false
        }
        openEditor()
        settle(1)
        any("saveButton").tap()
        XCTAssertTrue(any("saveToPhotos").waitForExistence(timeout: 5))
        any("saveToPhotos").tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01)).tap() // lets the interruption monitor run if a system alert appeared
        let toast = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Saved to Photos'")).firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: 40), "saved confirmation is shown")
        shot("15-saved-to-photos")
    }

    func testFirstUseIntroExplainsTheGesturesAndPinchIsOptional() {
        launch(introSeen: false)
        openEditor()
        XCTAssertTrue(app.staticTexts["Move and zoom with one finger"].waitForExistence(timeout: 10), "first-use explanation appears")
        XCTAssertTrue(app.staticTexts["4. ZOOM: slide one finger up to zoom in, down to zoom out. Tiny movements make tiny changes."].exists)
        XCTAssertTrue(app.switches["pinchToggle"].exists, "pinch is an optional preference")
        shot("16-gesture-intro")
        app.switches["pinchToggle"].firstMatch.tap()
        any("gotIt").tap()
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        any("touchHelp").tap()
        XCTAssertTrue(app.staticTexts["Move and zoom with one finger"].waitForExistence(timeout: 5), "the ? button reopens it")
        any("gotIt").tap()
    }

    func testGridModeFlow() {
        launch()
        let tile = any("tile-Photo grid")
        XCTAssertTrue(tile.waitForExistence(timeout: 15))
        tile.tap()
        XCTAssertTrue(any("makeGrid").waitForExistence(timeout: 10), "grid asks how many columns")
        shot("17-grid-columns")
        any("makeGrid").tap()
        XCTAssertTrue(canvas.waitForExistence(timeout: 30))
        settle(1.2)
        shot("18-grid-editor")
    }

    func testFamilyModeOpensFacesPanel() {
        launch()
        openEditor(tile: "tile-Family")
        XCTAssertTrue(app.staticTexts["Automatic positioning"].waitForExistence(timeout: 10), "family mode starts on the Faces tab")
        settle(1.5)
        shot("19-family-editor")
    }

    func testCompareMode() {
        launch()
        openEditor(tile: "tile-Side by side")
        settle(1.2)
        shot("20-compare-editor")
    }

    func testProjectsAreSavedAndShownAfterRelaunch() {
        launch()
        openEditor()
        settle(1.5)
        any("backButton").tap()
        XCTAssertTrue(any("createCollage").waitForExistence(timeout: 15))
        app.terminate()
        launch(reset: false)
        let recent = any("recent-My collage")
        XCTAssertTrue(recent.waitForExistence(timeout: 20), "the saved project is listed after relaunch")
        settle(1); shot("21-home-with-project")
        recent.tap()
        XCTAssertTrue(canvas.waitForExistence(timeout: 20), "and reopens")
    }

    func testRenameAndTemplateFlow() {
        launch()
        openEditor()
        settle(1)
        any("projectName").tap()
        let alert = app.alerts["Rename project"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let field = alert.textFields.firstMatch
        field.tap()
        field.clearAndType("Beach day")
        alert.buttons["Rename"].tap()
        XCTAssertTrue(app.buttons["Project name Beach day. Tap to rename."].firstMatch.waitForExistence(timeout: 5))
        any("saveTemplate").tap()
        let t = app.alerts["Save as template"]
        XCTAssertTrue(t.waitForExistence(timeout: 5))
        t.textFields.firstMatch.tap()
        t.textFields.firstMatch.typeText("Mine")
        t.buttons["Save"].tap()
        any("backButton").tap()
        let card = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Use template Mine'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15), "the template is on the home screen")
        shot("22-home-with-template")
    }

    func testDarkAppearance() {
        launch(extra: ["-UITestTheme", "dark"])
        XCTAssertTrue(any("createCollage").waitForExistence(timeout: 15))
        settle(); shot("23-home-dark")
        openEditor()
        settle(1.5)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.25)).tap()
        settle(0.8); shot("24-editor-dark")
    }

    func testLandscapeEditorKeepsAllControlsReachable() {
        launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        openEditor()
        settle(1.5)
        XCTAssertTrue(canvas.exists)
        XCTAssertTrue(any("modeZoom").exists)
        shot("25-editor-landscape")
        XCUIDevice.shared.orientation = .portrait
    }
}

private extension XCUIElement {
    func clearAndType(_ text: String) {
        guard let current = value as? String, !current.isEmpty else { typeText(text); return }
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        typeText(text)
    }
}
