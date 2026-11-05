import Foundation

/// Versioned JSON (de)serialisation of projects and templates, using the same keys as the Android app so files stay
/// interchangeable. Unknown / missing fields fall back to defaults so old files keep opening after the format grows.
enum ProjectJson {
    typealias Dict = [String: Any]

    enum JsonError: Error { case invalid(String) }

    // MARK: encode

    private static func rectJson(_ r: FRect) -> [Double] { [r.l, r.t, r.r, r.b] }
    private static func signed(_ c: ARGB) -> Int { Int(Int32(bitPattern: c)) }

    private static func photoJson(_ p: PhotoRef) -> Dict {
        var d: Dict = ["id": p.id, "file": p.file, "w": p.width, "h": p.height, "exif": p.exif]
        if let f = p.faces { d["faces"] = f.map(rectJson) }
        return d
    }

    private static func adjustJson(_ a: Adjustments) -> Dict {
        ["brightness": a.brightness, "contrast": a.contrast, "saturation": a.saturation, "warmth": a.warmth, "sharpness": a.sharpness]
    }

    private static func cellJson(_ c: CellEdit) -> Dict {
        var d: Dict = [
            "zoom": c.zoom, "cx": c.cx, "cy": c.cy, "rotation": c.rotation, "mirror": c.mirror, "fit": c.fit, "manual": c.manual,
            "adjust": adjustJson(c.adjustments), "filter": c.filter.rawValue,
            "caption": ["name": c.caption.name, "relation": c.caption.relation, "age": c.caption.age],
        ]
        if let p = c.photo { d["photo"] = photoJson(p) }
        return d
    }

    private static func textJson(_ t: TextOverlay) -> Dict {
        [
            "id": t.id, "text": t.text, "x": t.x, "y": t.y, "size": t.size, "color": signed(t.color), "font": t.font.rawValue,
            "bold": t.bold, "italic": t.italic, "align": t.align.rawValue, "shadow": t.shadow, "bg": signed(t.backgroundColor), "rot": t.rotation,
        ]
    }

    private static func backgroundJson(_ b: CanvasBackground) -> Dict {
        ["type": b.type.rawValue, "c1": signed(b.color1), "c2": signed(b.color2), "texture": b.texture.rawValue, "angle": b.angle]
    }

    private static func styleJson(_ s: CollageStyle) -> Dict {
        ["spacing": s.spacing, "margin": s.margin, "radius": s.cornerRadius, "border": s.borderWidth, "borderColor": signed(s.borderColor)]
    }

    private static func canvasJson(_ c: CanvasSpec) -> Dict { ["w": c.ratioW, "h": c.ratioH, "label": c.label] }

    private static func layoutJson(_ l: LayoutTemplate) -> Dict { ["id": l.id, "name": l.name, "cells": l.cells.map(rectJson)] }

    static func toDict(_ p: CollageProject) -> Dict {
        [
            "version": p.version, "id": p.id, "name": p.name, "createdAt": p.createdAt, "updatedAt": p.updatedAt,
            "mode": p.mode.rawValue, "canvas": canvasJson(p.canvas), "layout": layoutJson(p.layout), "style": styleJson(p.style),
            "background": backgroundJson(p.background), "cells": p.cells.map(cellJson), "texts": p.texts.map(textJson),
            "faceMode": p.faceMode.rawValue,
        ]
    }

    static func serialize(_ p: CollageProject) throws -> Data {
        try JSONSerialization.data(withJSONObject: toDict(p), options: [])
    }

    static func toDict(_ t: SavedTemplate) -> Dict {
        [
            "id": t.id, "name": t.name, "mode": t.mode.rawValue, "canvas": canvasJson(t.canvas), "layout": layoutJson(t.layout),
            "style": styleJson(t.style), "background": backgroundJson(t.background),
        ]
    }

    // MARK: decode helpers

    private static func double(_ d: Dict, _ k: String, _ def: Double) -> Double { (d[k] as? NSNumber)?.doubleValue ?? def }
    private static func int(_ d: Dict, _ k: String, _ def: Int) -> Int { (d[k] as? NSNumber)?.intValue ?? def }
    private static func bool(_ d: Dict, _ k: String, _ def: Bool) -> Bool { (d[k] as? NSNumber)?.boolValue ?? def }
    private static func string(_ d: Dict, _ k: String, _ def: String) -> String { d[k] as? String ?? def }
    private static func color(_ d: Dict, _ k: String, _ def: ARGB) -> ARGB {
        guard let n = d[k] as? NSNumber else { return def }
        return ARGB(truncatingIfNeeded: n.int64Value)
    }
    private static func enumOf<E: RawRepresentable>(_ d: Dict, _ k: String, _ def: E) -> E where E.RawValue == String {
        (d[k] as? String).flatMap { E(rawValue: $0) } ?? def
    }

    private static func readRect(_ a: Any?) -> FRect? {
        guard let arr = a as? [Any], arr.count >= 4 else { return nil }
        let v = arr.compactMap { ($0 as? NSNumber)?.doubleValue }
        return v.count >= 4 ? FRect(v[0], v[1], v[2], v[3]) : nil
    }

    private static func readPhoto(_ d: Dict) throws -> PhotoRef {
        guard let id = d["id"] as? String, let file = d["file"] as? String,
              let w = (d["w"] as? NSNumber)?.intValue, let h = (d["h"] as? NSNumber)?.intValue else { throw JsonError.invalid("photo") }
        var faces: [FRect]? = nil
        if let arr = d["faces"] as? [Any] { faces = arr.compactMap(readRect) }
        return PhotoRef(id: id, file: file, width: w, height: h, exif: int(d, "exif", 1), faces: faces)
    }

    private static func readAdjust(_ d: Dict?) -> Adjustments {
        guard let d = d else { return Adjustments() }
        return Adjustments(
            brightness: double(d, "brightness", 0), contrast: double(d, "contrast", 0), saturation: double(d, "saturation", 0),
            warmth: double(d, "warmth", 0), sharpness: double(d, "sharpness", 0)
        )
    }

    private static func readCell(_ d: Dict) -> CellEdit {
        let cap = d["caption"] as? Dict
        return CellEdit(
            photo: (d["photo"] as? Dict).flatMap { try? readPhoto($0) },
            zoom: double(d, "zoom", 1), cx: double(d, "cx", 0.5), cy: double(d, "cy", 0.5),
            rotation: int(d, "rotation", 0), mirror: bool(d, "mirror", false), fit: bool(d, "fit", false), manual: bool(d, "manual", false),
            adjustments: readAdjust(d["adjust"] as? Dict), filter: enumOf(d, "filter", FilterType.none),
            caption: CellCaption(name: cap.map { string($0, "name", "") } ?? "", relation: cap.map { string($0, "relation", "") } ?? "", age: cap.map { string($0, "age", "") } ?? "")
        )
    }

    private static func readText(_ d: Dict) throws -> TextOverlay {
        guard let id = d["id"] as? String else { throw JsonError.invalid("text") }
        return TextOverlay(
            id: id, text: string(d, "text", ""), x: double(d, "x", 0.5), y: double(d, "y", 0.9), size: double(d, "size", 0.06),
            color: color(d, "color", 0xFFFFFFFF), font: enumOf(d, "font", FontChoice.sans), bold: bool(d, "bold", false),
            italic: bool(d, "italic", false), align: enumOf(d, "align", TextAlign.center), shadow: bool(d, "shadow", true),
            backgroundColor: color(d, "bg", 0), rotation: double(d, "rot", 0)
        )
    }

    private static func readBackground(_ d: Dict?) -> CanvasBackground {
        guard let d = d else { return CanvasBackground() }
        return CanvasBackground(
            type: enumOf(d, "type", BackgroundType.solid), color1: color(d, "c1", 0xFFFFFFFF), color2: color(d, "c2", 0xFFE9E4DC),
            texture: enumOf(d, "texture", TextureKind.paper), angle: double(d, "angle", 90)
        )
    }

    private static func readStyle(_ d: Dict?) -> CollageStyle {
        guard let d = d else { return CollageStyle() }
        return CollageStyle(
            spacing: double(d, "spacing", 0.012), margin: double(d, "margin", 0.012), cornerRadius: double(d, "radius", 0.03),
            borderWidth: double(d, "border", 0), borderColor: color(d, "borderColor", 0xFFFFFFFF)
        )
    }

    private static func readCanvas(_ d: Dict?) -> CanvasSpec {
        guard let d = d else { return .square }
        let w = min(max(int(d, "w", 1), 1), 99), h = min(max(int(d, "h", 1), 1), 99)
        return CanvasSpec(w, h, label: string(d, "label", "\(w):\(h)"))
    }

    private static func readLayout(_ d: Dict) throws -> LayoutTemplate {
        guard let id = d["id"] as? String, let arr = d["cells"] as? [Any] else { throw JsonError.invalid("layout") }
        let cells = arr.compactMap(readRect)
        guard !cells.isEmpty, cells.count == arr.count else { throw JsonError.invalid("layout cells") }
        return LayoutTemplate(id: id, name: string(d, "name", ""), cells: cells)
    }

    static func parseProject(_ data: Data) throws -> CollageProject {
        guard let o = try JSONSerialization.jsonObject(with: data) as? Dict else { throw JsonError.invalid("root") }
        return try parseProject(o)
    }

    static func parseProject(_ o: Dict) throws -> CollageProject {
        guard let id = o["id"] as? String, let layoutDict = o["layout"] as? Dict else { throw JsonError.invalid("project") }
        let layout = try readLayout(layoutDict)
        let cellsArr = (o["cells"] as? [Any])?.compactMap { $0 as? Dict } ?? []
        let cells = cellsArr.map(readCell)
        let texts = try ((o["texts"] as? [Any])?.compactMap { $0 as? Dict } ?? []).map(readText)
        return CollageProject(
            version: CollageProject.currentVersion, id: id, name: string(o, "name", "Untitled collage"),
            createdAt: (o["createdAt"] as? NSNumber)?.int64Value ?? 0, updatedAt: (o["updatedAt"] as? NSNumber)?.int64Value ?? 0,
            mode: enumOf(o, "mode", ProjectMode.collage), canvas: readCanvas(o["canvas"] as? Dict), layout: layout,
            style: readStyle(o["style"] as? Dict), background: readBackground(o["background"] as? Dict),
            // pad/trim so cells always match the layout
            cells: (0..<layout.count).map { $0 < cells.count ? cells[$0] : CellEdit() },
            texts: texts, faceMode: enumOf(o, "faceMode", FaceMode.smart)
        )
    }

    static func parseTemplate(_ o: Dict) throws -> SavedTemplate {
        guard let id = o["id"] as? String, let layoutDict = o["layout"] as? Dict else { throw JsonError.invalid("template") }
        return SavedTemplate(
            id: id, name: string(o, "name", "Template"), mode: enumOf(o, "mode", ProjectMode.collage),
            canvas: readCanvas(o["canvas"] as? Dict), layout: try readLayout(layoutDict),
            style: readStyle(o["style"] as? Dict), background: readBackground(o["background"] as? Dict)
        )
    }
}
