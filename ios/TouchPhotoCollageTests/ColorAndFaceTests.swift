import XCTest
@testable import TouchPhotoCollage

final class ColorTests: XCTestCase {
    private func apply(_ m: [Double], _ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double, Double) {
        ColorMath.apply(m, r: r, g: g, b: b)
    }

    func testNeutralSettingsAreIdentity() {
        XCTAssertTrue(ColorMath.isIdentity(ColorMath.forCell(Adjustments(), .none)))
        XCTAssertTrue(Adjustments().isNeutral)
    }

    func testBlackAndWhiteRemovesColour() {
        let (r, g, b, _) = apply(ColorMath.filter(.blackWhite), 200, 100, 50)
        XCTAssertEqual(r, g, accuracy: 0.5); XCTAssertEqual(g, b, accuracy: 0.5)
    }

    func testBrightnessAndContrastMoveValuesInTheRightDirection() {
        XCTAssertEqual(apply(ColorMath.brightness(0.5), 100, 100, 100).0, 151, accuracy: 0.5)
        XCTAssertLessThan(apply(ColorMath.contrast(0.5), 100, 100, 100).0, 100)
        XCTAssertGreaterThan(apply(ColorMath.contrast(0.5), 200, 200, 200).0, 200)
        XCTAssertGreaterThan(apply(ColorMath.contrast(-0.5), 100, 100, 100).0, 100)
    }

    func testSaturationZeroIsGreyAndWarmthShiftsRedBlue() {
        let grey = apply(ColorMath.saturation(0), 255, 0, 0)
        XCTAssertEqual(grey.0, 0.2126 * 255, accuracy: 0.5)
        XCTAssertEqual(grey.0, grey.1, accuracy: 0.5)
        let warm = apply(ColorMath.warmth(1), 100, 100, 100)
        XCTAssertGreaterThan(warm.0, 100); XCTAssertLessThan(warm.2, 100)
        let cool = apply(ColorMath.warmth(-1), 100, 100, 100)
        XCTAssertLessThan(cool.0, 100); XCTAssertGreaterThan(cool.2, 100)
    }

    func testVintageIsNotIdentityAndKeepsAlpha() {
        let m = ColorMath.filter(.vintage)
        XCTAssertFalse(ColorMath.isIdentity(m))
        XCTAssertEqual(apply(m, 120, 130, 140).3, 255, accuracy: 1e-6)
    }

    func testEveryFilterProducesAValidMatrix() {
        for f in FilterType.allCases {
            let m = ColorMath.filter(f)
            XCTAssertEqual(m.count, 20)
            XCTAssertEqual(ColorMath.isIdentity(m), f == .none, "\(f)")
        }
    }

    func testSharpenLeavesFlatAreasAndBoostsEdges() {
        let w = 6, h = 3
        var src = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h { for x in 0..<w {
            let v: UInt8 = x < 3 ? 50 : 200
            let i = (y * w + x) * 4
            src[i] = v; src[i + 1] = v; src[i + 2] = v; src[i + 3] = 255
        } }
        let out = Sharpen.apply(src, w: w, h: h, amount: 1)
        XCTAssertEqual(out[(1 * w + 1) * 4], 50, "flat area unchanged")
        XCTAssertLessThan(out[(1 * w + 2) * 4], 50, "dark side of the edge gets darker")
        XCTAssertGreaterThan(out[(1 * w + 3) * 4], 199, "bright side of the edge gets brighter")
        XCTAssertEqual(out[(1 * w + 2) * 4 + 3], 255, "alpha preserved")
        XCTAssertEqual(Sharpen.apply(src, w: w, h: h, amount: 0), src)
    }
}

final class FaceCropTests: XCTestCase {
    private func faceAt(_ cx: Double, _ cy: Double, _ h: Double, _ aspect: Double) -> FRect {
        let w = h / aspect // square on screen when the image aspect is `aspect`
        return FRect(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2)
    }

    private func region(_ input: FaceInput, _ s: CropState) -> CropMath.Region {
        CropMath.region(imgAspect: input.imgAspect, cellAspect: input.cellAspect, zoom: s.zoom, cx: s.cx, cy: s.cy, fit: input.fit)
    }

    private func faceHeightInCell(_ input: FaceInput, _ s: CropState) -> Double {
        FaceCrop.primary(input.faces)!.h / region(input, s).visH
    }

    private func faceCentreY(_ input: FaceInput, _ s: CropState) -> Double {
        let r = region(input, s)
        return (FaceCrop.primary(input.faces)!.cy - r.rect.t) / r.visH
    }

    func testNoFaceFallsBackToCentreCrop() {
        let s = FaceCrop.smart(FaceInput(imgAspect: 1.5, faces: [], cellAspect: 1))
        XCTAssertEqual(s, CropState(zoom: 1, cx: 0.5, cy: 0.5))
    }

    func testSmartCropKeepsFacesVisibleEvenWhenOffCentre() {
        let input = FaceInput(imgAspect: 1.5, faces: [FRect(0.85, 0.3, 0.95, 0.5)], cellAspect: 1)
        let s = FaceCrop.smart(input)
        XCTAssertTrue(FaceCrop.facesVisible(input, s))
        XCTAssertGreaterThan(s.cx, 0.5)
    }

    func testAlignMatchesFaceSizeAndHeightAcrossGenerations() {
        let a = FaceInput(imgAspect: 1, faces: [FRect(0.4, 0.3, 0.6, 0.5)], cellAspect: 1)
        let b = FaceInput(imgAspect: 1, faces: [FRect(0.45, 0.35, 0.55, 0.45)], cellAspect: 1)
        let states = FaceCrop.align([a, b])
        let ha = faceHeightInCell(a, states[0]), hb = faceHeightInCell(b, states[1])
        XCTAssertEqual(ha, hb, accuracy: 0.01)
        XCTAssertEqual(ha, FaceCrop.desiredFaceHeight, accuracy: 0.01)
        XCTAssertEqual(faceCentreY(a, states[0]), FaceCrop.targetY, accuracy: 0.02)
        XCTAssertEqual(faceCentreY(b, states[1]), FaceCrop.targetY, accuracy: 0.02)
    }

    func testAlignNeverDistortsOnlyUniformZoom() {
        let inputs = [
            FaceInput(imgAspect: 0.75, faces: [FRect(0.4, 0.2, 0.6, 0.4)], cellAspect: 1.2),
            FaceInput(imgAspect: 1.8, faces: [FRect(0.1, 0.4, 0.2, 0.6)], cellAspect: 1.2),
        ]
        for (i, s) in FaceCrop.align(inputs).enumerated() {
            let r = region(inputs[i], s)
            XCTAssertEqual(r.visW / r.visH * inputs[i].imgAspect, inputs[i].cellAspect, accuracy: 1e-3)
            XCTAssertGreaterThanOrEqual(s.zoom, 1)
        }
    }

    func testPhotosWithoutFacesStayCentredWhileOthersAlign() {
        let withFace = FaceInput(imgAspect: 1, faces: [FRect(0.2, 0.2, 0.3, 0.3)], cellAspect: 1)
        let without = FaceInput(imgAspect: 1, faces: [], cellAspect: 1)
        let s = FaceCrop.align([withFace, without])
        XCTAssertEqual(s[1], CropState(zoom: 1, cx: 0.5, cy: 0.5))
        XCTAssertGreaterThan(s[0].zoom, 1)
    }
}
