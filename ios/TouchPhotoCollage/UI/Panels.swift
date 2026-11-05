import SwiftUI

private func pct(_ v: Double) -> String { String(format: "%.1f%%", v * 100) }

/// Layout candidates are pure functions of the photo count; cache them so panel redraws stay cheap.
@MainActor
enum LayoutCache {
    private static var store: [Int: [LayoutTemplate]] = [:]

    static func candidates(_ n: Int) -> [LayoutTemplate] {
        if let c = store[n] { return c }
        let c = LayoutGenerator.candidates(n)
        store[n] = c
        return c
    }
}

// MARK: Layout

struct LayoutPanel: View {
    let model: AppModel
    let p: CollageProject
    @State private var customCanvas = false
    @State private var saveTemplate = false
    @State private var wText = ""
    @State private var hText = ""
    @State private var templateName = ""

    var body: some View {
        let candidates = LayoutCache.candidates(p.layout.count)
        let isPreset = CanvasSpec.presets.contains { $0.sameRatio(p.canvas) }
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Arrangement")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    VStack(spacing: 2) {
                        Button { model.autoLayout() } label: {
                            Image(systemName: "sparkles").font(.system(size: 20))
                                .frame(width: 56, height: 56)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.outline, lineWidth: 1))
                                .foregroundColor(Palette.primary)
                        }
                        .buttonStyle(.plain).accessibilityLabel("Auto layout").accessibilityIdentifier("autoLayout")
                        Text("Auto").font(.labelSmall).foregroundColor(Palette.onSurfaceVariant)
                    }
                    .frame(width: 72)
                    ForEach(candidates, id: \.id) { l in
                        LayoutThumb(layout: l, aspect: p.canvas.aspect, selected: l.id == p.layout.id, label: l.name) { model.setLayout(l) }
                    }
                    if p.layout.id.hasPrefix("mosaic") && !candidates.contains(where: { $0.id == p.layout.id }) {
                        LayoutThumb(layout: p.layout, aspect: p.canvas.aspect, selected: true, label: "Artistic") {}
                    }
                }
            }
            HStack(spacing: 8) {
                if p.layout.count >= 2 {
                    Button { model.shuffleArtistic() } label: { Label("Shuffle artistic", systemImage: "dice").font(.labelLarge) }
                        .buttonStyle(.bordered).tint(Palette.primary).accessibilityIdentifier("shuffleArtistic")
                }
                Button { templateName = ""; saveTemplate = true } label: { Label("Save as template", systemImage: "square.and.arrow.down").font(.labelLarge) }
                    .buttonStyle(.bordered).tint(Palette.primary).accessibilityIdentifier("saveTemplate")
            }
            SectionLabel("Canvas shape")
            ChipRow {
                ForEach(CanvasSpec.presets, id: \.label) { c in
                    SelectChip(c.friendlyName, p.canvas.sameRatio(c)) { model.setCanvas(c) }
                }
                SelectChip(isPreset ? "Custom…" : "Custom \(p.canvas.label)", !isPreset) {
                    wText = String(p.canvas.ratioW); hText = String(p.canvas.ratioH); customCanvas = true
                }
            }
        }
        .alert("Custom canvas ratio", isPresented: $customCanvas) {
            TextField("Width", text: $wText).keyboardType(.numberPad)
            TextField("Height", text: $hText).keyboardType(.numberPad)
            Button("Apply") {
                if let a = Int(wText), let b = Int(hText), a > 0, b > 0 { model.setCanvas(CanvasSpec.custom(a, b)) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter the width and height of the shape, for example 5 and 7.")
        }
        .alert("Save as template", isPresented: $saveTemplate) {
            TextField("Template name", text: $templateName)
            Button("Save") { model.saveTemplate(String(templateName.prefix(30))) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Keeps the arrangement, canvas shape, spacing and background (not the photos).")
        }
    }
}

// MARK: Style

struct StylePanel: View {
    let model: AppModel
    let p: CollageProject

    var body: some View {
        let bg = p.background
        VStack(alignment: .leading, spacing: 6) {
            LabeledSlider(label: "Spacing", value: p.style.spacing, range: 0...0.08, onChange: { v in model.setStyle { $0.spacing = v } }, onDone: model.endLive, valueText: pct)
            LabeledSlider(label: "Margin", value: p.style.margin, range: 0...0.1, onChange: { v in model.setStyle { $0.margin = v } }, onDone: model.endLive, valueText: pct)
            LabeledSlider(label: "Rounded corners", value: p.style.cornerRadius, range: 0...0.2, onChange: { v in model.setStyle { $0.cornerRadius = v } }, onDone: model.endLive) { $0 < 0.002 ? "Square" : pct($0) }
            LabeledSlider(label: "Photo border", value: p.style.borderWidth, range: 0...0.03, onChange: { v in model.setStyle { $0.borderWidth = v } }, onDone: model.endLive) { $0 < 0.0005 ? "None" : pct($0) }
            if p.style.borderWidth > 0 {
                ColorSwatches(selected: p.style.borderColor) { c in model.setStyle(live: false) { $0.borderColor = c } }
            }

            SectionLabel("Background").padding(.top, 6)
            ChipRow {
                SelectChip("Colour", bg.type == .solid) { var b = bg; b.type = .solid; model.setBackground(b) }
                SelectChip("Gradient", bg.type == .gradient) {
                    var b = bg; b.type = .gradient
                    if b.color2 == b.color1 { b.color2 = 0xFFE8613C }
                    model.setBackground(b)
                }
                ForEach(TextureKind.allCases, id: \.self) { t in
                    SelectChip(t.rawValue.capitalized, bg.type == .texture && bg.texture == t) {
                        var b = bg; b.type = .texture; b.texture = t
                        b.color2 = (b.color1 == 0xFF1C1B1F || b.color1 == 0xFF424242) ? 0xFFFFFFFF : 0xFF8A7A5A
                        model.setBackground(b)
                    }
                }
                SelectChip("Transparent", bg.type == .transparent) { var b = bg; b.type = .transparent; model.setBackground(b) }
            }
            if bg.type != .transparent {
                SectionLabel(bg.type == .gradient || bg.type == .texture ? "Base colour" : "Colour")
                ColorSwatches(selected: bg.color1) { c in var b = bg; b.color1 = c; model.setBackground(b) }
                if bg.type == .gradient {
                    SectionLabel("Second colour")
                    ColorSwatches(selected: bg.color2) { c in var b = bg; b.color2 = c; model.setBackground(b) }
                    LabeledSlider(label: "Angle", value: bg.angle, range: 0...360, onChange: { v in var b = bg; b.angle = v; model.setBackground(b) }, onDone: {}) { "\(Int($0))°" }
                }
                if bg.type == .texture {
                    SectionLabel("Pattern colour")
                    ColorSwatches(selected: bg.color2) { c in var b = bg; b.color2 = c; model.setBackground(b) }
                }
            } else {
                TinyLabel("Transparent backgrounds are kept when you export as PNG. JPEG uses white.")
            }
        }
    }
}

// MARK: Adjust

private let filters: [(FilterType, String)] = [
    (.none, "Original"), (.blackWhite, "Black & white"), (.vintage, "Vintage"), (.sepia, "Sepia"),
    (.fade, "Fade"), (.vivid, "Vivid"), (.warm, "Warm"), (.cool, "Cool"),
]

struct AdjustPanel: View {
    let model: AppModel
    let p: CollageProject
    let selected: Int?
    @State private var applyAll = false

    var body: some View {
        let target: Int? = applyAll ? nil : selected
        let cellIndex = selected ?? p.cells.firstIndex { $0.photo != nil }
        if let ci = cellIndex, p.cells.indices.contains(ci) {
            let cell = p.cells[ci]
            let a = cell.adjustments
            let update: (Bool, @escaping (inout CellEdit) -> Void) -> Void = { live, f in
                if let t = target { model.editCell(t, live: live, f) } else { model.editAllCells(live: live, f) }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(applyAll ? "Editing all photos" : (selected != nil ? "Editing photo \(selected! + 1)" : "Tap a photo to edit it on its own"))
                        .font(.labelLarge)
                    Spacer()
                    Text("All photos").font(.labelMedium)
                    Toggle("All photos", isOn: Binding(get: { applyAll || selected == nil }, set: { applyAll = $0 }))
                        .labelsHidden().tint(Palette.primary).disabled(selected == nil)
                }
                ChipRow {
                    ForEach(filters, id: \.0) { f in
                        SelectChip(f.1, cell.filter == f.0) { update(false) { $0.filter = f.0 } }
                    }
                }
                LabeledSlider(label: "Brightness", value: a.brightness, range: -1...1, onChange: { v in update(true) { $0.adjustments.brightness = v } }, onDone: model.endLive)
                LabeledSlider(label: "Contrast", value: a.contrast, range: -1...1, onChange: { v in update(true) { $0.adjustments.contrast = v } }, onDone: model.endLive)
                LabeledSlider(label: "Saturation", value: a.saturation, range: -1...1, onChange: { v in update(true) { $0.adjustments.saturation = v } }, onDone: model.endLive)
                LabeledSlider(label: "Warmth", value: a.warmth, range: -1...1, onChange: { v in update(true) { $0.adjustments.warmth = v } }, onDone: model.endLive)
                LabeledSlider(label: "Sharpness", value: a.sharpness, range: 0...1, onChange: { v in update(true) { $0.adjustments.sharpness = v } }, onDone: model.endLive)
                Button("Reset adjustments") { update(false) { $0.adjustments = Adjustments(); $0.filter = .none } }
                    .font(.labelLarge).foregroundColor(Palette.primary).frame(minHeight: 44)
                TinyLabel("Edits are applied on top of your original photos. The originals are never changed.")
            }
        } else {
            Text("Add a photo to start editing.").font(.bodyMedium)
        }
    }
}

// MARK: Text

struct TextPanel: View {
    let model: AppModel
    let p: CollageProject
    let selectedText: Int?

    var body: some View {
        let t = selectedText.flatMap { p.texts.indices.contains($0) ? p.texts[$0] : nil }
        VStack(alignment: .leading, spacing: 6) {
            ChipRow {
                Button { model.addText("Your text") } label: { Label("Add text", systemImage: "plus").font(.labelLarge) }
                    .buttonStyle(.borderedProminent).tint(Palette.primary).accessibilityIdentifier("addText")
                Button { model.addText(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .none)) } label: { Label("Today's date", systemImage: "calendar").font(.labelLarge) }
                    .buttonStyle(.bordered).tint(Palette.primary)
                Button { model.addText("Name") } label: { Text("Name").font(.labelLarge) }.buttonStyle(.bordered).tint(Palette.primary)
                Button { model.addText("Caption") } label: { Text("Caption").font(.labelLarge) }.buttonStyle(.bordered).tint(Palette.primary)
            }
            if p.texts.count > 1 {
                ChipRow {
                    ForEach(Array(p.texts.enumerated()), id: \.offset) { i, x in
                        SelectChip(x.text.isEmpty ? "Text \(i + 1)" : String(x.text.prefix(14)), i == selectedText) { model.selectText(i) }
                    }
                }
            }
            if let t = t, let i = selectedText {
                TextField("Text", text: Binding(get: { t.text }, set: { v in model.editText(i, live: true) { $0.text = String(v.prefix(120)) } }), axis: .vertical)
                    .lineLimit(1...3).textFieldStyle(.roundedBorder).onSubmit { model.endLive() }
                    .accessibilityIdentifier("overlayText")
                SectionLabel("Font")
                ChipRow { ForEach(FontChoice.allCases, id: \.self) { f in SelectChip(f.label, t.font == f) { model.editText(i) { $0.font = f } } } }
                LabeledSlider(label: "Size", value: t.size, range: 0.02...0.2, onChange: { v in model.editText(i, live: true) { $0.size = v } }, onDone: model.endLive)
                SectionLabel("Colour")
                ColorSwatches(selected: t.color) { c in model.editText(i) { $0.color = c } }
                ChipRow {
                    SelectChip("Bold", t.bold) { model.editText(i) { $0.bold.toggle() } }
                    SelectChip("Italic", t.italic) { model.editText(i) { $0.italic.toggle() } }
                    SelectChip("Shadow", t.shadow) { model.editText(i) { $0.shadow.toggle() } }
                    SelectChip("Label box", t.backgroundColor != 0) { model.editText(i) { $0.backgroundColor = $0.backgroundColor == 0 ? 0x99000000 : 0 } }
                    ForEach(TextAlign.allCases, id: \.self) { al in SelectChip(al.rawValue.capitalized, t.align == al) { model.editText(i) { $0.align = al } } }
                }
                LabeledSlider(label: "Tilt", value: t.rotation, range: -45...45, onChange: { v in model.editText(i, live: true) { $0.rotation = v } }, onDone: model.endLive) { "\(Int($0))°" }
                Button("Delete this text", role: .destructive) { model.deleteText(i) }.frame(minHeight: 44).accessibilityIdentifier("deleteText")
            } else {
                TinyLabel(p.texts.isEmpty ? "Add names, dates and captions. Drag text on the picture to move it." : "Tap text on the picture, or pick one above, to edit it.")
            }
        }
    }
}

// MARK: Faces

struct FacesPanel: View {
    let model: AppModel
    let p: CollageProject
    let selected: Int?
    let facesPending: Int

    var body: some View {
        let analysed = p.cells.compactMap { $0.photo }
        let found = analysed.filter { !($0.faces ?? []).isEmpty }.count
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Automatic positioning")
            ChipRow {
                SelectChip("Centre only", p.faceMode == .off) { model.setFaceMode(.off) }
                SelectChip("Keep faces in frame", p.faceMode == .smart) { model.setFaceMode(.smart) }
                SelectChip("Align faces", p.faceMode == .align) { model.setFaceMode(.align) }
            }
            Text({ () -> String in
                switch p.faceMode {
                case .off: return "Photos are centred. Drag any photo to place it yourself."
                case .smart: return "Each photo is centred on the people in it."
                case .align: return "Faces are matched in size and height so relatives line up. Photos are only scaled evenly, never stretched."
                }
            }()).font(.bodyMedium).foregroundColor(Palette.onSurfaceVariant)
            Text(
                facesPending > 0 ? "Looking for faces on this device… (\(facesPending) left)"
                : (p.faceMode != .off && found == 0 ? "No faces found, so photos are centred. You can still drag and zoom each one."
                   : "Faces found in \(found) of \(analysed.count) photos. Detection runs on your phone only.")
            ).font(.labelMedium)
            HStack {
                VStack(alignment: .leading) {
                    Text("Never crop my photos").font(.labelLarge)
                    TinyLabel("Show each whole photo, with bars instead of cropping")
                }
                Spacer()
                Toggle("Never crop my photos", isOn: Binding(
                    get: { !analysed.isEmpty && p.cells.filter { $0.photo != nil }.allSatisfy { $0.fit } },
                    set: { model.setAvoidCropping($0) }
                )).labelsHidden().tint(Palette.primary).accessibilityIdentifier("neverCrop")
            }
            Button("Redo automatic positioning for all photos") { model.resetCrops() }
                .font(.labelLarge).foregroundColor(Palette.primary).frame(minHeight: 44)

            if let s = selected, p.cells.indices.contains(s), p.cells[s].photo != nil {
                let c = p.cells[s].caption
                SectionLabel(p.mode == .family ? "About this person" : "Caption on this photo")
                TextField("Name", text: Binding(get: { c.name }, set: { v in model.editCell(s, live: true) { $0.caption.name = String(v.prefix(24)) } }))
                    .textFieldStyle(.roundedBorder).onSubmit { model.endLive() }.accessibilityIdentifier("captionName")
                HStack(spacing: 8) {
                    TextField("Relationship", text: Binding(get: { c.relation }, set: { v in model.editCell(s, live: true) { $0.caption.relation = String(v.prefix(20)) } }))
                        .textFieldStyle(.roundedBorder).onSubmit { model.endLive() }
                    TextField("Age", text: Binding(get: { c.age }, set: { v in model.editCell(s, live: true) { $0.caption.age = String(v.prefix(10)) } }))
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 90).onSubmit { model.endLive() }
                }
                TinyLabel("Captions appear along the bottom of the photo. Leave all blank for none.")
            } else {
                TinyLabel("Tap a photo to add a name, relationship and age caption.")
            }
        }
    }
}
